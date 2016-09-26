local template = require"resty.mvc.template"
local encode = require "cjson.safe".encode
local DEBUG = require"app.settings".DEBUG
local APP = require"app.settings".APP
local open = io.open
local sub = string.sub

local vars = ngx.var

local function readfile(path)
    local file = open(path, "rb")
    if not file then return nil end
    local content = file:read "*a"
    file:close()
    return content
end
local root = vars.document_root or ngx.config.prefix()
if sub(root, -1) == "/" then 
    root = sub(root, 1, -2) 
end
local function app_loader( path )
    local res = readfile(table.concat{ root, "/", path })
    if not res then
        for i, name in ipairs(APP) do
            res = readfile(table.concat{"app/", name, "/html/", path })
            if res then
                break
            end
        end
    end
    return res or path
end
template.load = app_loader

local template_cache;
if DEBUG then
    template_cache = 'no-cache'
end

local GLOBAL_CONTEXT = {pjl='yeal'}

local compile = template.compile
local function render(request, path, context)
    local res = {}
    for k,v in pairs(GLOBAL_CONTEXT) do
        res[k] = v
    end
    res.request = request
    res.user = request.user
    res.message = request.message
    --res.messages = request.messages
    if context then
        for k,v in pairs(context) do
            res[k] = v
        end
    end
    return compile(path, template_cache)(res)
end

local M = {}
function M.new(self, init)
    init = init or {}
    self.__index = self
    return setmetatable(init, self)
end

local PlainMeta = M:new{}
PlainMeta.__call = function(tbl, text)
    return tbl:new{text=text}
end

local Plain = PlainMeta:new{}
function Plain.exec(self)
    ngx.header['Content-Type'] = "text/plain; charset=utf-8"
    return ngx.print(self.text)
end

local HtmlMeta = M:new{}
HtmlMeta.__call = function(tbl, text)
    return tbl:new{text=text}
end

local Html = HtmlMeta:new{}
function Html.exec(self)
    ngx.header['Content-Type'] = "text/html; charset=utf-8"
    return ngx.print(self.text)
end

local TemplateMeta = M:new{}
TemplateMeta.__call = function(tbl, request, path, context)
    return tbl:new{path=path, context=context, request=request}
end

local Template = TemplateMeta:new{}
function Template.exec(self)
    ngx.header['Content-Type'] = "text/html; charset=utf-8"
    return ngx.print(render(self.request, self.path, self.context))
end

local ErrorMeta = M:new{}
ErrorMeta.__call = function(tbl, message)
    return tbl:new{message=message}
end

local Error = ErrorMeta:new{}
function Error.exec(self)
    ngx.header['Content-Type'] = "text/html; charset=utf-8"
    return ngx.print(compile('error.html')({message=self.message}))
end

local RedirectMeta = M:new{}
RedirectMeta.__call = function(tbl, url, status)
    return tbl:new{url=url, status=status or 302}
end

local Redirect = RedirectMeta:new{}
function Redirect.exec(self)
    return ngx.redirect(self.url, self.status)
end

local JsonMeta = M:new{}
JsonMeta.__call = function(tbl, jsondict)
    return tbl:new{jsondict=jsondict}
end

local Json = JsonMeta:new{}
function Json.exec(self)
    ngx.header['Content-Type'] = "application/json; charset=utf-8"
    return ngx.print(encode(self.jsondict))
end



return {
    Template = Template, 
    Json = Json, 
    Redirect = Redirect, 
    Plain = Plain, 
    Html = Html, 
    Error = Error, 
}