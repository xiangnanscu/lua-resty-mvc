-- https://dev.mysql.com/doc/refman/5.6/en/create-table.html
-- http://dev.mysql.com/doc/refman/5.6/en/create-table-foreign-keys.html
-- https://dev.mysql.com/doc/refman/5.6/en/create-index.html
-- http://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html
local query = require"resty.mvc.query".single

local function make_file(fn, content)
  local f, e = io.open(fn, "w+")
  if not f then
    return nil, e
  end
  local res, err = f:write(content)
  if not res then
    return nil, err
  end
  local res, err = f:close()
  if not res then
    return nil, err
  end
  return true
end
local function serialize_defaut(s)
    if type(s)=='string' then
        s=string.format("%q",s)
    elseif s == false then
        return 0
    elseif s == true then
        return 1
    elseif type(s) =='number' then
        return tostring(s)
    elseif type(s) == 'function' then
        return serialize_defaut(s())
    else
        assert(nil, 'type `'..type(s)..'` is not supported as a default value')
    end
end

local function make_table_defination(model)
    local joiner = ',\n    '
    local field_options = {}
    local table_options = {}
    local fields = {}
    local meta = model.meta
    local pk_not_done = true

    table_options[#table_options+1] = 'DEFAULT CHARSET='..meta.charset

    for name, field in pairs(model.fields) do
        -- name  == field.name
        local field_string
        local db_type = field.db_type
        local field_type = field:get_internal_type()

        if field_type =='ForeignKey' then
            if not field_options.foreign_key then
                field_options.foreign_key = {}
            end
            table.insert(field_options.foreign_key, string.format(
                'FOREIGN KEY (%s) REFERENCES %s(id) ON DELETE %s ON UPDATE %s', 
                name, field.reference.table_name, field.on_delete or 'CASCADE', field.on_update or 'CASCADE'))
            -- todo allow null
            field_string = string.format('%s INT UNSIGNED NOT NULL', name)
        elseif field_type == 'AutoField' then
            assert(pk_not_done, 'you could set only one primary key')
            assert(name=='id', 'primary key name must be `id`')
            field_string = 'id INT UNSIGNED NOT NULL AUTO_INCREMENT UNIQUE PRIMARY KEY'
            pk_not_done = false
        else
            if db_type =='VARCHAR' then
                db_type = string.format('VARCHAR(%s)', field.maxlen)
            end
            if field.index then
                if not field_options.index then
                    field_options.index = {}
                end        
                table.insert(field_options.index, string.format('INDEX (%s)', name))
            end                
            if field.default ~= nil then
                db_type = db_type..' DEFAULT '..serialize_defaut(field.default)
            end
            if field.unique then
                db_type = db_type..' UNIQUE'
            end       
            if field.null then
                db_type = db_type..' NULL'
            else
                db_type = db_type..' NOT NULL'
            end    
            field_string = string.format('%s %s', name, db_type)
        end
        fields[#fields+1] = field_string
    end

    local fields = table.concat(fields, joiner)

    local _op = {}
    for k,v in pairs(field_options) do -- flatten field_options
        if type(v) == 'table' then
            for i,e in ipairs(v) do
                _op[#_op+1] = e
            end
        else
            _op[#_op+1] = v
        end
    end
    local field_options = table.concat(_op, joiner)
    if field_options ~= '' then
        field_options = ',\n    '..field_options
    end

    local table_options = table.concat(table_options, ' ')

    local table_create_defination = string.format([[CREATE TABLE %s(%s%s)%s;]], 
        model.table_name, fields, field_options, table_options)

    return table_create_defination
end

local function get_table_defination(table_name)
    local res, err = query('show create table '..table_name..';')
    if not res then
        return nil, err
    end
    return res[1]["Create Table"]
end

local function write_model_to_db(model, drop_existed_table)
    local res, err = query(string.format("SHOW TABLES LIKE '%s'", model.table_name))
    if not res then
        assert(nil, err)
    end
    if #res ~= 0 and not drop_existed_table then
        return
    end
    local table_create_defination = make_table_defination(model)
    local res, err = query('DROP TABLE IF EXISTS '..model.table_name)
    if not res then
        assert(nil, err)
    end
    local res, err = query(table_create_defination)
    if not res then
        assert(nil, err)
    end
    return get_table_defination(model.table_name)
end
local function has_values(t, e)
    for k, v in pairs(t) do
        if v == e then
            return true
        end
    end
    return false
end

local function get_models()
    -- default function to get models list
    local res = {}
    for i, name in ipairs(settings.APP) do
        local models = require("app."..name..".models")
        for name, model in pairs(models) do
            res[#res+1] = model
        end
    end
    return res
end

local function migrate_models(models, drop_existed_table)
    local res = {}
    -- name: User, model: User
    for i, model in ipairs(models) do
        local insert_index = nil
        for i, e in ipairs(res) do
            if has_values(e.foreignkeys, model) then
                insert_index = i
                break
            end
        end
        table.insert(res, insert_index or #res+1, model)
    end

    if drop_existed_table then    
        for i = #res, 1, -1 do
            local r, err = query('DROP TABLE IF EXISTS '..res[i].table_name)
            if not r then
                assert(nil, err)
            end
        end
    end

    local defs = {}
    for i, model in ipairs(res) do
        defs[#defs+1] = write_model_to_db(model, drop_existed_table)
    end
    return defs
end

local function main(get_models_func, drop_existed_table)
    local models
    get_models_func = get_models_func or get_models
    if type(get_models_func) == 'function' then
        models = get_models_func()
    elseif type(get_models_func) == 'table' then
        models = get_models_func
    else
        assert(nil, 'invalid argument, should be either a function or table.')
    end
    return migrate_models(models, drop_existed_table)
end


return main