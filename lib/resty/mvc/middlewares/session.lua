-- based on https://github.com/openresty/encrypted-session-nginx-module
-- and https://github.com/openresty/set-misc-nginx-module
local json = require "cjson.safe"
local settings = require"resty.mvc.settings"
local tonumber = tonumber
local ngx_time = ngx.time
local ngx_http_time = ngx.http_time

local SESSION_PATH, SESSION_EXPIRES
if settings.SESSION then
    SESSION_PATH = settings.SESSION.path or '/'
    SESSION_EXPIRES = settings.SESSION.expires or 30*24*3600 -- 30 days
else
    SESSION_PATH = '/'
    SESSION_EXPIRES = 30*24*3600 -- 30 days
end

local encrypt_callbacks = {
    json.encode, 
    ndk.set_var.set_encrypt_session, 
    ndk.set_var.set_encode_base64, 
}
local decrypt_callbacks = {
    ndk.set_var.set_decode_base64, 
    ndk.set_var.set_decrypt_session, 
    json.decode, 
}
local function encrypt_session(value)
    for i, en in ipairs(encrypt_callbacks) do
        value = en(value)
        if not value then 
            return nil 
        end
    end
    return value
end
local function decrypt_session(value)
    if not value then 
        return {}
    end
    for i, de in ipairs(decrypt_callbacks) do
        value = de(value)
        if not value then 
            return {} 
        end
    end
    return value
end

local process_request, process_response
function process_request(request)
    local LazySessionMeta = {}
    local function __index(t, k)
        local data = decrypt_session(request.cookies.session)
        request._session = data
        LazySessionMeta.__index = data
        return data[k]     
    end
    local function __newindex(t, k, v)
        local data = request._session
        if not data then
            data = decrypt_session(request.cookies.session)
            request._session = data
            LazySessionMeta.__index = data
        end
        request.session_has_changed = true
        LazySessionMeta.__newindex = data
        data[k] = v
    end
    LazySessionMeta.__index = __index
    LazySessionMeta.__newindex = __newindex
    request.session = setmetatable({}, LazySessionMeta)
end

function process_response(request, response)
    if request.session_has_changed then
        local data = request._session
        if next(data) == nil then
            response.cookies.session = nil
        else
            response.cookies.session = {
                value = encrypt_session(data), 
                path = SESSION_PATH, 
                max_age = SESSION_EXPIRES, 
                -- expires = ngx_http_time(ngx_time() + SESSION_EXPIRES),
            }
        end
    end
    return response
end


return { process_request = process_request, process_response = process_response}