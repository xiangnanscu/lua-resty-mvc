local query = require"resty.mvc.query".single
local Row = require"resty.mvc.row"
local Manager = require"resty.mvc.manager" 
local Field = require"resty.mvc.modelfield"
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
        auto_id=true, 
        charset = 'utf8', 
    }, 
}

function Model.new(self, opts)
    opts = opts or {}
    self.__index = self
    return setmetatable(opts, self)
end
local RELATIONS = {
    lt='%s < %s', lte='%s <= %s', gt='%s > %s', gte='%s >= %s', 
    ne='%s <> %s', eq='%s = %s', ['in']='%s IN %s', 
    exact = '%s = %s', iexact = '%s COLLATE UTF8_GENERAL_CI = %s',}
function Model.class(cls, attrs)
    local subclass = cls:new(attrs)
    assert(not subclass.table_name:find('__'), 'double underline `__` is not allowed in a table name')

    if rawget(subclass, 'meta') == nil then
        subclass.meta = {}
    end
    local parent_meta = getmetatable(subclass).meta
    setmetatable(subclass.meta, {__index=parent_meta})

    subclass.row_class = Row:new{table_name=subclass.table_name, fields=subclass.fields}
    subclass.foreignkeys = {}
    local all_fields = {} 
    if subclass.meta.auto_id then
        subclass.fields.id = Field.AutoField{primary_key=true}
    end
    for name, field in pairs(subclass.fields) do
        field.name = name
        assert(not RELATIONS[name], name..' can not be used as a column name')
        local errors = field:check()
        assert(not next(errors), name..' check fails:'..table_concat(errors, ', '))
        if field:get_internal_type() == 'ForeignKey' then
            subclass.foreignkeys[name] = field.reference
        end
        all_fields[#all_fields+1] = string_format("`%s`.`%s`", subclass.table_name, name)
    end
    subclass.fields_string = table_concat(all_fields, ', ') -- to replace '*' in `Manager:select` clause
    -- field_order
    if not subclass.field_order then
        local field_order = {}
        for k, v in pairs(subclass.fields) do
            field_order[#field_order+1] = k
        end
        subclass.field_order = field_order
    end
    return subclass
end
function Model.instance(cls, attrs, commit)
    local ins = cls.row_class:new(attrs)
    if commit then
        local res, errors = ins:create()
        if not res then
            return nil, errors
        else
            return ins
        end
    else
        return ins
    end
end

function Model._proxy_sql(self, method, params)
    local proxy = Manager:new{table_name=self.table_name, fields=self.fields, 
        row_class=self.row_class, foreignkeys=self.foreignkeys, fields_string=self.fields_string}
    return proxy[method](proxy, params)
end
local chain_methods = {"select", "where", "update", "create", "delete", "group", "order", "having", "page", "join"}
-- define methods by a loop, `create` will be override
for i, method_name in ipairs(chain_methods) do
    Model[method_name] = function(self, params)
        return self:_proxy_sql(method_name, params)
    end
end
function Model.get(self, params)
    -- params cannot be empty table
    local res, err = self:_proxy_sql('where', params):exec()
    if not res then
        return nil, err
    elseif #res~=1 then
        return nil, 'should return 1 row, but get '..#res
    end
    return self.row_class:instance(res[1])
end
function Model.all(self)
    -- special process for `all`
    local res, err = query(string_format('SELECT * FROM `%s`;', self.table_name))
    if not res then
        return nil, err
    end
    local row_class = self.row_class
    for i, attrs in ipairs(res) do
        res[i] = row_class:instance(attrs)
    end
    return res
end
return Model