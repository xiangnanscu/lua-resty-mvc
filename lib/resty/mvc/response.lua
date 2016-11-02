local template = require"resty.mvc.template"
local settings = require"resty.mvc.settings"
local encode = require "cjson.safe".encode
local utils = require"resty.mvc.utils"
local bake = require"resty.mvc.cookie".bake
local open = io.open

--@./resty/mvc/response.lua
--@/usr/local/openresty/site/lualib/resty/response.lua
--ADMIN_DIR = './resty/mvc/html/'
local ADMIN_DIR = (debug.getinfo(1,"S").source:match'^@(.*)response.lua$')..'html/'
local COOKIE_PATH = settings.COOKIE.path
local COOKIE_EXPIRES = settings.COOKIE.expires
local GLOBAL_CONTEXT = {
    __domain='example.com',
}
local TEMPLATE_DIRS = settings.TEMPLATE_DIRS

local function smart_set_cookie(t, k, v)
    -- k can't be `__save`, `__index`, `__newindex`
    if type(v) == 'string' then
        v = {value = v,  path = COOKIE_PATH, max_age = COOKIE_EXPIRES}  
    elseif v == nil then
        v = {value = '', path = COOKIE_PATH, max_age = 0} 
    end
    rawset(t, k, v)
end
local SetCookieMeta = {__newindex = smart_set_cookie}

local function HttpResponseCaller(t, ...)
    return t:instance(...)
end
local HttpResponse = {}
function HttpResponse.new(cls, self)
    self = self or {}
    cls.__index = cls
    cls.__call = HttpResponseCaller
    return setmetatable(self, cls)
end
function HttpResponse.instance(cls, attrs)
    -- body, content_type
    local self = cls:new(attrs)
    self.headers = {content_type = self.content_type or 'text/html; charset=utf-8'}
    self.cookies = setmetatable({}, SetCookieMeta)
    return self
end
function HttpResponse.exec(self)
    self:exec_headers()
    return ngx.print(self.body)
end
function HttpResponse.exec_headers(self)
    local c = {}
    for k, v in pairs(self.cookies) do
        v.key = k
        c[#c + 1] = bake(v)
    end
    ngx.header['Set-Cookie'] = c
    for k, v in pairs(self.headers) do
        ngx.header[k] = v
    end
end

local function readfile(path)
    local file = open(path, "rb")
    if not file then 
        return nil 
    end
    local content = file:read"*a"
    file:close()
    return content
end
local default_loader = template.load
local function admin_loader(path)
    return readfile(ADMIN_DIR..path) or path
end

local function app_loader(path)
    for i, dir in ipairs(TEMPLATE_DIRS) do
        local res = readfile(dir..path)
        if res then
            return res
        end
    end
    return path
end
template.loaders = {default_loader, app_loader, admin_loader}
local function load_from_loaders(path)
    -- first try lua-resty-template's loader
    local res
    for i, loader in ipairs(template.loaders) do
        res = loader(path)
        if res ~= nil and res ~= path then
            return res
        end
    end
    return path
end
template.load = load_from_loaders
local compile = template.compile

local TemplateResponse = HttpResponse:new()
TemplateResponse.__call = HttpResponseCaller
function TemplateResponse.instance(cls, request, path, context)
    local self = HttpResponse.instance(cls, {
        request = request, path = path, context = context})
    return self
end
function TemplateResponse.render(self)
    local request = self.request
    local utils_context =  {
        request = request,
        user = request.user,
        message = request.message,
    }
    return compile(self.path)(utils.dict(GLOBAL_CONTEXT, utils_context, self.context))
end

local JsonResponse = HttpResponse:new()
JsonResponse.__call = HttpResponseCaller
function JsonResponse.instance(cls, jsondict)
    local self = HttpResponse.instance(cls, 
        {body = encode(jsondict),
        content_type = 'application/json; charset=utf-8'})
    return self
end

local PlainResponse = HttpResponse:new()
PlainResponse.__call = HttpResponseCaller
function PlainResponse.instance(cls, attrs)
    attrs = attrs or {}
    attrs.content_type = 'text/plain; charset=utf-8'
    local self = HttpResponse.instance(cls, attrs)
    return self
end

local HttpRedirect = HttpResponse:new()
HttpRedirect.__call = HttpResponseCaller
function HttpRedirect.instance(cls, url, status)
    local self = HttpResponse.instance(cls, {
        url = url,
        status = status or 302})
    return self
end
function HttpRedirect.exec(self)
    self:exec_headers()
    return ngx.redirect(self.url, self.status)
end

local ErrorResponse = HttpResponse:new()
ErrorResponse.__call = HttpResponseCaller
if settings.DEBUG then
    function ErrorResponse.instance(cls, message)
        message = message or '500 internal server error'
        message = message..'\n\n'..utils.repr(_G, 10)
        local self = HttpResponse.instance(cls, {content_type='text/plain; charset=utf-8', body=message})
        return self
    end
else
    function ErrorResponse.instance(cls, message)
        message = message or '500 internal server error'
        local self = HttpResponse.instance(cls, {content_type='text/plain; charset=utf-8', body=message})
        return self
    end
end

return {
    HttpResponse = HttpResponse,
    Plain = PlainResponse,
    Error = ErrorResponse,
    Template = TemplateResponse,
    Json = JsonResponse, 
    Redirect = HttpRedirect, 
}