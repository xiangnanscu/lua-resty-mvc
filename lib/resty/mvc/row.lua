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

-- `Row` is the main api for create, update and delete a database record
-- the instance of `Row` should be a plain table, i.e. key should be a valid lua variable name, 
-- value should be either a string or a number. if value is a boolean or table and you
-- want to save it to database, you should provide a `lua_to_db` method for that field to convert 
-- the value to string or number. Currently no hook to convert the value read from database to
-- non-string or non-number. For exmaple, a BooleanField value read from database will be number
-- 0 or 1. a DateTimeField value will be a plain string.
local Row = {}
function Row.new(cls, attrs)
    attrs = attrs or {}
    cls.__index = cls
    return setmetatable(attrs, cls)
end
function Row.instance(cls, attrs)
    -- attrs may be from db driver, try to use `db_to_lua` if the field specified
    local self = cls:new(attrs)
    local fields = self.fields
    for k, v in pairs(self) do
        local f = fields[k]
        if f and f.db_to_lua then
            self[k] = f:db_to_lua(v)
        end
    end
    return self
end
function Row.create(self)
    local valid_attrs = {}
    local all_errors = {}
    for name, field in pairs(self.fields) do
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
            local value, errors = field:clean(value)
            if errors then
                for i, v in ipairs(errors) do
                    all_errors[#all_errors+1] = v
                end
            else
                if field.lua_to_db then
                    value = field:lua_to_db(value)
                end
                valid_attrs[name] = value
            end
        end
    end
    if next(all_errors) then
        return nil, all_errors
    end
    local res, err = query(string_format( 'INSERT INTO `%s` SET %s;', 
        self.table_name, utils.serialize_attrs(valid_attrs, self.table_name)))
    if res then
        self.id = res.insert_id
        return res
    else
        return nil, {err}
    end
end
function Row.update(self)
    local valid_attrs = {}
    local all_errors = {}
    for name, field in pairs(self.fields) do
        if field.auto_now then
            -- note we check the existence of `auto_now` before the value
            -- this is different from Row.create, becuase we want to update the time 
            -- to now every time we update a row even if a value is provided for this field
            valid_attrs[name] = ngx_localtime()
        else
            local value = self[name]
            if value == nil then
                -- do nothing 
            else
                local value, errors = field:clean(value)
                if errors then
                    for i, v in ipairs(errors) do
                        all_errors[#all_errors+1] = v
                    end
                else
                    if field.lua_to_db then
                        value = field:lua_to_db(value)
                    end
                    valid_attrs[name] = value
                end
            end
        end
    end
    if next(all_errors) then
        return nil, all_errors
    end
    local res, err = query(string_format( 'UPDATE `%s` SET %s WHERE id=%s;', 
        self.table_name, utils.serialize_attrs(valid_attrs, self.table_name), self.id))
    if res then
        return res
    else
        return nil, {err}
    end
end
-- *_without_clean is used when you're sure no need to perform validations, 
-- e.g. when the a string comes from `resty.mvc.form` cleaned_data. 
-- note, `lua_to_db` is still used to ensure correct type saved to database.
function Row.create_without_clean(self)
    local valid_attrs = {}
    for name, field in pairs(self.fields) do
        local value = self[name]
        if value == nil then
            if field.default then
                valid_attrs[name] = field:get_default()
            elseif field.auto_now or field.auto_now_add then
                valid_attrs[name] = ngx_localtime()
            end
        else
            if field.lua_to_db then
                value = field:lua_to_db(value)
            end
            valid_attrs[name] = value
        end
    end
    local res, err = query(string_format( 'INSERT INTO `%s` SET %s;', 
        self.table_name, utils.serialize_attrs(valid_attrs, self.table_name)))
    if res then
        self.id = res.insert_id
        return res
    else
        return nil, {err}
    end
end
function Row.update_without_clean(self)
    local valid_attrs = {}
    for name, field in pairs(self.fields) do
        if field.auto_now then
            valid_attrs[name] = ngx_localtime()
        else
            local value = self[name]
            if value == nil then
                -- do nothing 
            else
                if field.lua_to_db then
                    value = field:lua_to_db(value)
                end
                valid_attrs[name] = value
            end
        end
    end
    local res, err = query(string_format('UPDATE `%s` SET %s WHERE id=%s;', 
        self.table_name, utils.serialize_attrs(valid_attrs, self.table_name), self.id))
    if res then
        return res
    else
        return nil, {err}
    end
end
function Row.direct_save(self, add)
    -- directly pass the key/value to database without any validations or type checks.
    -- cautions to this api, you should use it internally
    local res, err
    if add then
        res, err = query(string_format( 'INSERT INTO `%s` SET %s;', 
            self.table_name, utils.serialize_attrs(self, self.table_name)))
        self.id = res.insert_id
    else
        res, err = query(string_format('UPDATE `%s` SET %s WHERE id=%s;', 
            self.table_name, utils.serialize_attrs(self, self.table_name), self.id))    
    end
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
function Row.delete(self)
    if not self.id then
        return nil, 'No id to delete'
    end
    return query(string_format('DELETE FROM `%s` WHERE id=%s;', self.table_name, self.id))
end

return Row