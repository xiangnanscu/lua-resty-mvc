local utils = require"resty.mvc.utils"
local Response = require"resty.mvc.response"
-- local settings = require"resty.mvc.settings"

local function login_user(request, user)
    request.session.user = {
        id = user.id,
        username = user.username,  
        permission = user.permission}
end

local function login_require(view_func)
    local function wrap_view(request)
        if not request.user then
            request.session.message = 'please login before doing this'
            return Response.Redirect('/login?redirect_url='..ngx.var.uri)
        else
            return view_func(request)
        end
    end
    return wrap_view
end

local function admin_login_require(view_func)
    local function wrap_view(request)
        if not request.user then
            request.session.message = 'please login before doing this'
            return Response.Redirect('/admin/login?redirect_url='..ngx.var.uri)
        else
            return view_func(request)
        end
    end
    return wrap_view
end

local function test_user(test_func, login_url)
    login_url = login_url or '/login'
    local function user_require(view_func)
        local function wrap_view(request)
            if not test_func(request.user) then
                request.session.message = 'admin permission required, please login before doing this'
                return Response.Redirect(string.format('%s?redirect_url=%s', login_url, ngx.var.uri))
            else
                return view_func(request)
            end
        end
        return wrap_view
    end
    return user_require
end

local admin_user_require = test_user(
    function(u) return u and u.permission == 's' end, '/admin/login')

local function get_user_model()
    local u = require"resty.mvc.settings".USER_MODEL
    if type(u) == 'string' then
        return require(u)
    elseif type(u) == 'table' then
        return require(u[1])[u[2]]
    elseif u == nil then
        return require('resty.mvc.apps.auth.models').User
    else
        assert(nil, 'invalid USER_MODEL value.')
    end
end

return {
    login_require = login_require,
    admin_login_require = admin_login_require,
    login_user = login_user, 
    get_user_model = utils.cache_result(get_user_model),
    admin_user_require = admin_user_require,
}