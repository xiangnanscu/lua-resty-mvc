local query = require"resty.mvc.query".single
local utils = require"resty.mvc.utils"
local rawget = rawget
local setmetatable = setmetatable
local pairs = pairs
local ipairs = ipairs
local next = next
local tostring = tostring
local type = type
local string_format = string.format
local table_concat = table.concat
local ngx_localtime = ngx.localtime


local function row_tostring(t)
    return t:render()
end
-- `Row` is the main api for create, update and delete a database record.
-- the instance of `Row` should be a plain table, i.e. key should be a valid lua variable name, 
-- value should be either a string or a number. if value is a boolean or table and you
-- want to save it to database, you should provide a `lua_to_db` method for that field to convert 
-- the value to string or number. 
local Row = {}
function Row.new(cls, attrs)
    attrs = attrs or {}
    cls.__index = cls
    cls.__tostring = row_tostring
    return setmetatable(attrs, cls)
end
function Row.render(self)
    return self.__model.render(self)
end
function Row.get_url(self)
    return self.__model.get_url(self)
end
function Row.get_update_url(self)
    return self.__model.get_update_url(self)
end
function Row.get_delete_url(self)
    return self.__model.get_delete_url(self)
end
function Row.instance(cls, attrs)
    -- make a row object from attrs from a db driver(lua-resty-mysql), 
    -- try to use `db_to_lua` to make some data suitable for lua's orm layer.
    -- such as data from DateTimeField or ForeignKey.
    local self = cls:new(attrs)
    local fields = self.__model.fields
    for k, v in pairs(self) do
        local f = fields[k]
        if f and f.db_to_lua then
            self[k] = f:db_to_lua(v)
        end
    end
    return self
end
local function _check_field_value(name, field, value, all_errors, valid_attrs)
    local value, errors = field:clean(value)
    if errors then
        for i, v in ipairs(errors) do
            all_errors[#all_errors+1] = v
        end
    else
        if field.lua_to_db then
            -- assume calling `lua_to_db` should always succeed
            value = field:lua_to_db(value)
        end
        valid_attrs[name] = value
    end
end
function Row.create(self)
    -- use this method before create a row to database
    assert(self.id == nil, 'field `id` should be nil')
    local valid_attrs = {}
    local all_errors = {}
    for name, field in pairs(self.__model.fields) do
        local value = self[name]
        if value == nil then
            -- no value, try to get from default or auto_now/auto_now_add
            if field.default then
                value = field:get_default()
            elseif field.auto_now or field.auto_now_add then
                value = ngx_localtime()
            end
            valid_attrs[name] = value
            self[name] = value
        else
            -- if value is given, auto_now/auto_now_add will be ignored
            _check_field_value(name, field, value, all_errors, valid_attrs)
        end
    end
    if next(all_errors) then
        return nil, all_errors
    end
    local res, err = query(string_format('INSERT INTO `%s` SET %s;', 
        self.__model.meta.table_name, utils.serialize_attrs(valid_attrs)))
    if res then
        self.id = res.insert_id
        return res
    else
        return nil, {err}
    end
end
function Row.update(self)
    -- use this method before update a row to database
    assert(self.id, 'field `id` should not be nil')
    local valid_attrs = {}
    local all_errors = {}
    for name, field in pairs(self.__model.fields) do
        if field.auto_now then
            -- note we check the existence of `auto_now` before checking the value
            -- this is different from Row.create, becuase a field with auto_now 
            -- should be done like this.
            valid_attrs[name] = ngx_localtime()
        else
            local value = self[name]
            if value ~= nil then
                _check_field_value(name, field, value, all_errors, valid_attrs)
            end
        end
    end
    if next(all_errors) then
        return nil, all_errors
    end
    local res, err = query(string_format('UPDATE `%s` SET %s WHERE id = %s;', 
        self.__model.meta.table_name, utils.serialize_attrs(valid_attrs), self.id))
    if res then
        return res
    else
        return nil, {err}
    end
end
function Row.save(self, add)
    if add then
        return self:create()
    end
    return self:update()
end
function Row.direct_create(self)
    local res, err = query(string_format('INSERT INTO `%s` SET %s;', 
        self.__model.meta.table_name, utils.serialize_attrs(self)))
    if not res then
        return nil, {err}
    end
    self.id = res.insert_id
    return res
end
function Row.direct_update(self)
    local res, err = query(string_format('UPDATE `%s` SET %s WHERE id = %s;', 
        self.__model.meta.table_name, utils.serialize_attrs(self), self.id)) 
    if not res then
        return nil, {err}
    end
    return res
end
function Row.direct_save(self, add)
    if add then
        return self:direct_create()
    end
    return self:direct_update()
end
function Row.delete(self)
    assert(self.id, 'field `id` should not be nil')
    return query(string_format('DELETE FROM `%s` WHERE id = %s;', 
        self.__model.meta.table_name, self.id))
end

return Row