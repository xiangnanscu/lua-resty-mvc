local ClassView = require"resty.mvc.view"
local views = require"resty.mvc.apps.auth.views"

return {
    {'/admin/login', views.login}, 
    {'/admin/logout', views.logout}, 
}
