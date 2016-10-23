-- All models and urls should be registered here and referenced by
-- calling functions `get_models` and `get_urls`.
-- Currently this module is required by:
--   resty.mvc.migrate
--   resty.mvc.response
-- which means you can't require these modules during this module(resty.mvc.apps)
-- is required. Or a loop error will raise.
local utils = require"resty.mvc.utils"
local settings = require"resty.mvc.settings"

-- directory where a app lives, relative to nginx running path
-- you need to end with `\` or `/`
local DIR = 'apps/' 
local PACKAGE_PREFIX = DIR:gsub('/','.'):gsub('\\','.') 
local NAMES = settings.APPS or utils.filter(
        utils.get_dirs(DIR), function(e) return not e:find('__') end)
local TEMPLATE_DIRS = utils.map(NAMES, function(e) return string.format('%s%s/html/', DIR, e) end)

local function normalize_model(model, app_name, model_name)
    local Field = require"resty.mvc.modelfield"
    local Row = require"resty.mvc.row"
    
    local cls = getmetatable(model)
    -- meta initialize
    local meta = {}
    for _, cls in ipairs(utils.reversed_inherited_chain(model)) do
        utils.dict_update(meta, cls.meta)
    end
    -- always overwrite
    meta.app_name = app_name
    meta.model_name = model_name
    -- table_name
    local table_name = meta.table_name
    if table_name then
        assert(not table_name:find('__'), 'double underline `__` is not allowed in a table name')
    else
        meta.table_name = string.format('%s_%s', app_name, model_name:lower())
    end
    -- field_order
    -- first set `id` field
    if meta.auto_id then
        model.fields.id = Field.AutoField{primary_key = true}
    end
    if not meta.field_order then
        local field_order = {}
        for k, v in utils.sorted(model.fields) do
            field_order[#field_order+1] = k
        end
        meta.field_order = field_order
    end
    -- fields_string
    meta.fields_string = table.concat(
        utils.map(meta.field_order, 
                  function(e) return string.format("`%s`.`%s`", meta.table_name, e) end), 
        ', ')
    -- url_model_name
    if not meta.url_model_name then
        meta.url_model_name = model_name:lower()
    end
    -- row class
    model.row_class = Row:new{__model=model}
    -- fields
    model.foreignkeys = {}
    for name, field in pairs(model.fields) do
        assert(not Row[name], name.." can't be used as a column name")
        field.name = name
        local errors = field:check()
        assert(not next(errors), name..' check fails: '..table.concat(errors, ', '))
        if field:get_internal_type() == 'ForeignKey' then
            model.foreignkeys[name] = field.reference
        end
    end
    model.meta = meta
    return model
end

local function get_models()
    local res = {}
    for i, app_name in ipairs(NAMES) do
        local models = require(PACKAGE_PREFIX..app_name..".models")
        for model_name, model in pairs(models) do
            -- app_name: accounts, model_name: User, table_name: accounts_user
            res[#res + 1] = normalize_model(model, app_name, model_name)
        end
    end
    if not settings.USER_MODEL then
        -- no user model specified, add the built-in user model
        res[#res + 1] = normalize_model(require'resty.mvc.apps.auth.models'.User, 'auth', 'User')
    end
    return res
end
get_models = utils.cache_result(get_models)

local function get_urls()
    local res = {}
    for i, name in ipairs(NAMES) do
        local urls = require(PACKAGE_PREFIX..name..".urls")
        for _, url in ipairs(urls) do
            res[#res+1] = url
        end
    end
    return res
end
get_urls = utils.cache_result(get_urls)

return {
    NAMES = NAMES,
    TEMPLATE_DIRS = TEMPLATE_DIRS,
    DIR = DIR,
    PACKAGE_PREFIX = PACKAGE_PREFIX,
    get_models = get_models, -- function to avoid loop require
    get_urls = get_urls, -- function to avoid loop require
}
