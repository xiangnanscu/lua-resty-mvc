-- All models and urls should be registered here and referenced by
-- calling functions `get_models` and `get_urls`.
-- Currently this module is required by:
--   resty.mvc.migrate
--   resty.mvc.response
-- which means you can't require these modules during this module(resty.mvc.apps)
-- is required. Or a loop error will raise.
-- local utils = require"resty.mvc.utils"
local settings = require"resty.mvc.settings"
-- directory where a app lives, relative to nginx running path
-- you need to end with `\` or `/`
local Apps = {
    dir = 'apps/' ,
    package_prefix = 'apps.',
}
Apps.__index = Apps
function Apps.new(cls, attrs)
    return setmetatable(attrs or {}, cls)
end
function Apps.register(self, model)
    assert(model.meta and model.meta.is_normalized, 'model should be normalized first.')
    local app_name = model.meta.app_name
    assert(not Apps[app_name], app_name..' is a invalid name.')
    if not self[app_name] then
        self[app_name] = {}
    end
    self[app_name][model.meta.model_name] = model
end
function Apps.get_models(self)
    local res = {}
    for app_name, models in pairs(self) do
        for model_name, model in pairs(models) do
            res[#res+1] = model
        end
    end
    return res
end
function Apps.get_urls(self)
    local res = {}
    for i, name in ipairs(settings.APPS) do
        local urls = require(self.package_prefix..name..".urls")
        for _, url in ipairs(urls) do
            res[#res+1] = url
        end
    end
    return res
end
function Apps.get_admin_urls(self)
    local utils = require"resty.mvc.utils"
    local Form = require"resty.mvc.form"
    local ClassView = require"resty.mvc.view"
    local auth = require"resty.mvc.auth"

    local models = self:get_models()

    local function form_factory(model, kwargs)
        local fields = {}
        for name, field in pairs(model.fields) do
            fields[name] = field:formfield(kwargs)
        end
        return Form:class{fields=fields, model=model}
    end
    local function admin_get_context_data(view, kwargs)
        kwargs = kwargs or {}
        kwargs.apps = self
        return ClassView.TemplateView.get_context_data(view, kwargs)
    end
    function admin_app_get_context_data(view, kwargs)
        kwargs = kwargs or {}
        local app_name = ngx.var.uri:match('^/admin/(%w+)$')
        kwargs.apps = {[app_name] = self[app_name]}
        return ClassView.TemplateView.get_context_data(view, kwargs)
    end
    local function redirect_to_admin_detail(view)
        return '/admin'..view.object:get_url()
    end
    local function redirect_to_admin_list(view)
        return '/admin'..view.object:get_list_url()
    end
    

    local urls = {
        {'/admin', ClassView.TemplateView:as_view{
            template_name = '/admin/home.html',
            get_context_data = admin_get_context_data}
        },
    }

    for app_name, models in pairs(self) do
        urls[#urls + 1] = {
            string.format('/admin/%s', app_name),
            ClassView.TemplateView:as_view{
                template_name = '/admin/home.html',
                get_context_data = admin_app_get_context_data,
            },
        }
        for model_name, model in pairs(models) do
            local url_model_name = model.meta.url_model_name
            urls[#urls + 1] = {
                string.format('/admin/%s/%s/list', app_name, url_model_name),
                ClassView.ListView:as_view{
                    model = model,
                    template_name = '/admin/list.html',
                },
            }
            urls[#urls + 1] = {
                string.format('/admin/%s/%s/create', app_name, url_model_name),
                ClassView.CreateView:as_view{
                    model = model,
                    form_class = form_factory(model),
                    template_name = '/admin/create.html',
                    get_success_url = redirect_to_admin_detail,
                },
            }
            urls[#urls + 1] = {
                string.format('/admin/%s/%s/update', app_name, url_model_name),
                ClassView.UpdateView:as_view{
                    model = model,
                    form_class = form_factory(model),
                    template_name = '/admin/update.html',
                    get_success_url = redirect_to_admin_detail,
                },
            }
            urls[#urls + 1] = {
                string.format('/admin/%s/%s', app_name, url_model_name),
                ClassView.DetailView:as_view{
                    model = model,
                    template_name = '/admin/detail.html',
                },
            }
            urls[#urls + 1] = {
                string.format('/admin/%s/%s/delete', app_name, url_model_name),
                ClassView.DeleteView:as_view{
                    model = model,
                    get_success_url = redirect_to_admin_list,
                },
            }
        end
    end
    return utils.list_extend(
        urls,
        --utils.map(urls, function(url) return {url[1], auth.admin_user_require(url[2])} end),
        auth.urls)
end

return Apps
