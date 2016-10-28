local Form = require"resty.mvc.form"
local Field = require"resty.mvc.formfield"
local Validator = require"resty.mvc.validator"
local json = require "cjson.safe"
local query = require"resty.mvc.query".single
local Response = require"resty.mvc.response"
local ClassView = require"resty.mvc.view"
local utils = require"resty.mvc.utils"

local User = require"apps.account.models".User

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


local LoginForm = Form:class{
    
    fields = {
        username = Field.CharField{maxlen=20, minlen=3},    
        password = Field.PasswordField{maxlen=128, minlen=3},    
    }, 

    -- ensure `username` is rendered and checked before `password`
    field_order = {'username', 'password'}, 
    
    clean_username = function(self, value)
        local user = User:get{username=value}
        if not user then
            return nil, {"username doesn't exist."}
        end
        if user.permission ~= 's' then
            return nil, {"you've no permission to login"}
        end
        self.user = user -- used in `clean_password` later
        return value
    end, 
    
    clean_password = function(self, value)
        if self.user then
            if self.user.password ~= value then
                return nil, {'wrong password.'}
            end
        end
        return value
    end, 
}

local function login(request)
    local redirect_url = request.GET.redirect_url or '/admin'
    if redirect_url == '/admin/login' then
        redirect_url = '/admin'
    end
    if request.user then
        request.session.message = "you've already login."
        return Response.Redirect(redirect_url)
    end
    local form;
    if request.get_method() == 'POST' then
        form = LoginForm:instance{data=request.POST}
        if form:is_valid() then
            login_user(request, form.user)
            request.session.message = "welcome, "..form.user.username
            if request:is_ajax() then
                local data = {valid=true, url=redirect_url}
                return Response.Json(data)
            else
                return Response.Redirect(redirect_url)
            end
        end
    else
        form = LoginForm:instance{}
    end
    if request:is_ajax() then
        local data = {valid=false, errors=form:errors()}
        return Response.Json(data)
    else
        return Response.Template(request, "admin/login.html", {form=form})
    end
end

local function logout(request)
    request.session.user = nil
    request.session.message = "goodbye"
    -- local r = ngx.req.get_headers().referer
    local r = ngx.var.http_referer
    return Response.Redirect(r or '/admin')
end

return {
    urls = {
        {'/admin/login',  login}, 
        {'/admin/logout', logout}, 
    },
    login_require = login_require,
    admin_login_require = admin_login_require,
    login_user = login_user, 
    admin_user_require = admin_user_require,
}