local bake = require"resty.mvc.cookie".bake
local get_cookie_table = require"resty.mvc.cookie".get_cookie_table
local settings = require"resty.mvc.settings"
local ngx_time = ngx.time
local ngx_http_time = ngx.http_time

local COOKIE_PATH, COOKIE_EXPIRES
if settings.COOKIE then
    COOKIE_PATH = settings.COOKIE.path or '/'
    COOKIE_EXPIRES = settings.COOKIE.expires or 30*24*3600 -- 30 days
else
    COOKIE_PATH = '/'
    COOKIE_EXPIRES = 30*24*3600 -- 30 days
end

local function process_request(request)
    request.cookies = get_cookie_table(ngx.var.http_cookie)
end

return { process_request = process_request }