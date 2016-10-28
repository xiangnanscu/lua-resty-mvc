local query = require"resty.mvc.query".single
local Manager = require"resty.mvc.manager" 
local Field = require"resty.mvc.modelfield"
local Row = require"resty.mvc.row"
local utils = require"resty.mvc.utils"
local rawget = rawget
local setmetatable = setmetatable
local ipairs = ipairs
local tostring = tostring
local type = type
local pairs = pairs
local string_format = string.format
local table_concat = table.concat
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR

local Model = {
    meta = {
        auto_id = true, 
        charset = 'utf8', 
    }, 
}
function Model.new(cls, attrs)
    attrs = attrs or {}
    cls.__index = cls
    return setmetatable(attrs, cls)
end
function Model.normalize(cls, app_name, model_name)
    -- meta initialize
    local meta = {}
    for _, model in ipairs(utils.reversed_inherited_chain(cls)) do
        utils.dict_update(meta, model.meta)
    end
    if meta.is_normalized then
        return cls
    end
    -- row class
    cls.row_class = Row:new{__model=cls}
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
        cls.fields.id = Field.AutoField{primary_key = true}
    end
    -- then set order
    if not meta.field_order then
        local field_order = {}
        for k, v in utils.sorted(cls.fields) do
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
    -- check fields
    cls.foreignkeys = {}
    for name, field in pairs(cls.fields) do
        assert(not Row[name], name.." can't be used as a column name")
        field.name = name
        local errors = field:check()
        assert(not next(errors), name..' check fails: '..table.concat(errors, ', '))
        if field:get_internal_type() == 'ForeignKey' then
            cls.foreignkeys[name] = field.reference
        end
    end
    meta.is_normalized = true
    cls.meta = meta
    return cls
end
------ row proxy methods -----
function Model.render(row)
    return string_format('[%s]', row.id)
end
function Model.get_url(row)
    local meta = row.__model.meta
    return string_format('/%s/%s?id=%s', meta.app_name, meta.url_model_name, row.id)
end
function Model.get_update_url(row)
    local meta = row.__model.meta
    return string_format('/%s/%s/update?id=%s', meta.app_name, meta.url_model_name, row.id)
end
function Model.get_delete_url(row)
    local meta = row.__model.meta
    return string_format('/%s/%s/delete?id=%s', meta.app_name, meta.url_model_name, row.id)
end
------ row proxy methods -----
function Model.instance(cls, attrs, commit)
    -- make row from client data, such as Form.cleaned_data.
    -- While `Row.instance` makes row from db.
    local row = cls.row_class:new(attrs)
    if commit then
        return row:create()
    else
        return row
    end
end
function Model._proxy_sql(cls, method, params)
    local proxy = Manager:new{__model=cls}
    return proxy[method](proxy, params)
end
-- define methods by a loop, `create` will be override
for i, method_name in ipairs({"select", "where", "update", "create", "delete", 
                              "group", "order", "having", "page", "join"}) do
    Model[method_name] = function(cls, params)
        return cls:_proxy_sql(method_name, params)
    end
end
function Model.get(cls, params)
    -- call `exec_raw` instead of `exec` here to avoid unneccessary 
    -- initialization of row instance for #res > 1 
    -- because join is impossible for this api, so no need to call `exec`.
    local res, err = cls:_proxy_sql('where', params):exec_raw()
    if not res then
        return nil, err
    elseif #res ~= 1 then
        return nil, 'should return 1 row, but get '..#res
    end
    return cls.row_class:instance(res[1])
end
function Model.all(cls)
    -- special process for `all`
    local res, err = query(string_format('SELECT * FROM `%s`;', cls.meta.table_name))
    if not res then
        return nil, err
    end
    for i=1, #res do
        res[i] = cls.row_class:instance(res[i])
    end
    return res
end

return Model