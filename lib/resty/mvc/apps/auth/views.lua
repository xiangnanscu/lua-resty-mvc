local json = require "cjson.safe"
local query = require"resty.mvc.query".single
local Response = require"resty.mvc.response"
local ClassView = require"resty.mvc.view"
local utils = require"resty.mvc.utils"
local forms = require"resty.mvc.apps.auth.forms"
local auth = require"resty.mvc.apps.auth"

local User = auth.get_user_model()


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
        form = forms.LoginForm:instance{data=request.POST}
        if form:is_valid() then
            auth.login_user(request, form.user)
            request.session.message = "welcome, "..form.user.username
            if request:is_ajax() then
                local data = {valid=true, url=redirect_url}
                return Response.Json(data)
            else
                return Response.Redirect(redirect_url)
            end
        end
    else
        form = forms.LoginForm:instance{}
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
    login = login, 
    logout = logout,
}