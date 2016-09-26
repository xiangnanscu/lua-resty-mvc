local query = require"resty.mvc.query".single
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

-- Although `Manager` can be used alone with `table_name`, `fields` and `row_class` specified, 
-- it is mainly used as a proxy for the `Model` api. Besides, `Manager` performs little checks 
-- such as whether a field is valid or a value is valid for a field.

-- Table 10.1 Special Character Escape Sequences

-- Escape Sequence Character Represented by Sequence
-- \0  An ASCII NUL (X'00') character
-- \'  A single quote (“'”) character
-- \"  A double quote (“"”) character
-- \b  A backspace character
-- \n  A newline (linefeed) character
-- \r  A carriage return character
-- \t  A tab character
-- \Z  ASCII 26 (Control+Z); see note following the table
-- \\  A backslash (“\”) character
-- \%  A “%” character; see note following the table
-- \_  A “_” character; see note following the table

local function execer(t) 
    return t:exec() 
end

local Manager = {}
function Manager.new(cls, attrs)
    attrs = attrs or {}
    cls.__index = cls
    cls.__unm = execer
    return setmetatable(attrs, cls)
end
local chain_methods = {
    "select", "where", "group", "having", "order", "page", 
    "create", "update", "delete", 
}
function Manager.flush(self)
    for i,v in ipairs(chain_methods) do
        self['_'..v] = nil
        self['_'..v..'_string'] = nil
    end
    self.is_select = nil
    return self
end
function Manager.exec_raw(self)
    return query(self:to_sql())
end
function Manager.exec(self)
    local statement = self:to_sql()
    local res, err = query(statement)
    if not res then
        return nil, err
    end
    if self.is_select and not(
        self._group or self._group_string or self._having or self._having_string) then
        -- none-group SELECT clause, wrap the results
        for i, attrs in ipairs(res) do
            res[i] = self.row_class:new(attrs)
        end
    end
    return res
end
function Manager.to_sql(self)
    if self._update_string then
        return string_format('UPDATE `%s` SET %s%s;', self.table_name, self._update_string,
            self._where_string and ' WHERE '..self._where_string or 
            self._where and ' WHERE '..utils.serialize_andkwargs(self._where, self.table_name) or '')
    elseif self._update then
        return string_format('UPDATE `%s` SET %s%s;', self.table_name, utils.serialize_attrs(self._update, self.table_name),
            self._where_string and ' WHERE '..self._where_string or 
            self._where and ' WHERE '..utils.serialize_andkwargs(self._where, self.table_name) or '')
    elseif self._create_string then
        return string_format('INSERT INTO `%s` SET %s;', self.table_name, self._create_string)
    elseif self._create then
        return string_format('INSERT INTO `%s` SET %s;', self.table_name, utils.serialize_attrs(self._create, self.table_name))
    -- delete always need WHERE clause in case truncate table    
    elseif self._delete_string then 
        return string_format('DELETE FROM `%s` WHERE %s;', self.table_name, self._delete_string)
    elseif self._delete then 
        return string_format('DELETE FROM `%s` WHERE %s;', self.table_name, utils.serialize_andkwargs(self._delete, self.table_name))
    --SELECT..FROM..WHERE..GROUP BY..HAVING..ORDER BY
    else 
        self.is_select = true --for the `exec` method
        local stm = string_format('SELECT %s FROM `%s`%s%s%s%s%s;', 
            self._select_string or self._select and utils.serialize_columns(self._select, self.table_name) or '*',  
            self.table_name, 
            self._where_string  and    ' WHERE '..self._where_string  or self._where  and ' WHERE '..utils.serialize_andkwargs(self._where, self.table_name)   or '', 
            self._group_string  and ' GROUP BY '..self._group_string  or self._group  and ' GROUP BY '..utils.serialize_columns(self._group, self.table_name)      or '', 
            self._having_string and   ' HAVING '..self._having_string or self._having and ' HAVING '..utils.serialize_andkwargs(self._having) or '', 
            self._order_string  and ' ORDER BY '..self._order_string  or self._order  and ' ORDER BY '..utils.serialize_columns(self._order, self.table_name)      or '', 
            self._page_string   and ' LIMIT '..self._page_string      or '')
        return stm
    end
end
-- function Manager.clean_params(self, params)
--     -- params passed to `create` and `update` need to:
--     -- 1) delete it or raise an error if a key is not in self.fields (currently delete it).
--     -- 2) call `to_db` method(if exists) to get value prepared for being saved to database
--     --    e.g. lua literal `true` or `false` may be passed to a BooleanField, which 
--     --    should be converted to 1 or 0 for database. Also in the future, a lua datetime object
--     --    may be passed to a DateTimeField, which should be converted to string for database. e.g.
--     --    params = {bool_field=true, datetime_field={year=2010, month=10, day=10, hour=0, minute=0, second=0}}
--     --    -> {bool_field=1, datetime_field='2010-10-10 00:00:00'}
--     -- 3) For more validation checks or auto-value settings, use api `create` or `update` of `resty.mvc.row`
--     for k,v in pairs(params) do
--         local f = self.fields[k]
--         if not f then
--             params[k] = nil
--         elseif f.to_db then
--             params[k] = f:to_db(v)
--         end
--     end
--     return params
-- end

-- local dict_methods =  {
--     "create", "update", "delete", "where","having",
-- }
-- local list_methods =  {
--     "select",  "group", 
--     -- "order",  
-- }
-- for i, name in ipairs(dict_methods) do
--     local function _method_defined_by_loop(self, params)
--         if type(params) == 'table' then
--             local m = '_'..name
--             if self[m] == nil then
--                 self[m] = {}
--             end
--             for k, v in pairs(params) do
--                 self[m][k] = v
--             end
--         else
--             self['_'..name..'_string'] = params
--         end
--         return self
--     end
--     Manager[name] = _method_defined_by_loop
-- end

-- chain methods. They look the same, but to be friendly for debugging and
-- to be easy for further custom logic writing, we decide not to define these
-- methods by a loop.
function Manager.create(self, params)
    if type(params) == 'table' then
        if self._create == nil then
            self._create = {}
        end
        local res = self._create
        for k, v in pairs(params) do
            res[k] = v
        end
    else
        self._create_string = params
    end
    return self
end
function Manager.update(self, params)
    if type(params) == 'table' then
        if self._update == nil then
            self._update = {}
        end
        local res = self._update
        for k, v in pairs(params) do
            res[k] = v
        end
    else
        self._update_string = params
    end
    return self
end
function Manager.delete(self, params)
    if type(params) == 'table' then
        if self._delete == nil then
            self._delete = {}
        end
        local res = self._delete
        for k, v in pairs(params) do
            res[k] = v
        end
    else
        self._delete_string = params
    end
    return self
end
function Manager.where(self, params)
    if type(params) == 'table' then
        if self._where == nil then
            self._where = {}
        end
        local res = self._where
        for k, v in pairs(params) do
            res[k] = v
        end
    else
        self._where_string = params
    end
    return self
end
function Manager.having(self, params)
    if type(params) == 'table' then
        if self._having == nil then
            self._having = {}
        end
        local res = self._having
        for k, v in pairs(params) do
            res[k] = v
        end
    else
        self._having_string = params
    end
    return self
end
function Manager.group(self, params)
    if type(params) == 'table' then
        if self._group == nil then
            self._group = {}
        end
        local res = self._group
        for i, v in ipairs(params) do
            res[#res+1] = v
        end
    else
        self._group_string = params
    end
    return self
end
function Manager.select(self, params)
    if type(params) == 'table' then
        if self._select == nil then
            self._select = {}
        end
        local res = self._select
        for i, v in ipairs(params) do
            res[#res+1] = v
        end
    else
        self._select_string = params
    end
    return self
end
function Manager.order(self, params)
    if type(params) == 'table' then
        if self._order == nil then
            self._order = {}
        end
        local res = self._order
        for i, v in ipairs(params) do
            if v:sub(1, 1) == '-' then
                -- convert '-key' to 'key desc'
                v = v:sub(2)..' desc'
            end
            res[#res+1] = v
        end
    else
        self._order_string = params
    end
    return self
end
function Manager.page(self, params)
    -- only accept string
    self._page_string = params
    return self
end
return Manager