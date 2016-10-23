-- https://dev.mysql.com/doc/refman/5.6/en/create-table.html
-- http://dev.mysql.com/doc/refman/5.6/en/create-table-foreign-keys.html
-- https://dev.mysql.com/doc/refman/5.6/en/create-index.html
-- http://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html
local query = require"resty.mvc.query".single
local utils = require"resty.mvc.utils"
local apps = require"resty.mvc.apps"


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
                name, field.reference.meta.table_name, field.on_delete or 'CASCADE', field.on_update or 'CASCADE'))
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
        model.meta.table_name, fields, field_options, table_options)

    return table_create_defination
end

local function get_table_defination(table_name)
    local res, err = query('show create table '..table_name..';')
    if not res then
        return nil, err
    end
    return res[1]["Create Table"]
end

local function save_model_to_db(model, drop_existed_table)
    local res, err = query(string.format("SHOW TABLES LIKE '%s'", model.meta.table_name))
    if not res then
        assert(nil, err)
    end
    if #res ~= 0 and not drop_existed_table then
        return
    end
    local table_create_defination = make_table_defination(model)
    local res, err = query('DROP TABLE IF EXISTS '..model.meta.table_name)
    if not res then
        assert(nil, err)
    end
    local res, err = query(table_create_defination)
    if not res then
        assert(nil, err)
    end
    return get_table_defination(model.meta.table_name)
end
local function get_models()
    return apps.get_models()
end

local function save_models_to_db(models, drop_existed_table)
    local res = {}
    -- sort the models to an array for table creation in database
    for _, model in ipairs(models) do
        local insert_index = nil
        for i, e in ipairs(res) do
            if utils.dict_has(e.foreignkeys, model) then
                -- table being foreign key referenced should be created first
                insert_index = i
                break
            end
        end
        table.insert(res, insert_index or #res+1, model)
    end

    if drop_existed_table then    
        for i = #res, 1, -1 do
            local r, err = query('DROP TABLE IF EXISTS '..res[i].meta.table_name)
            if not r then
                assert(nil, err)
            end
        end
    end

    local defs = {}
    for i, model in ipairs(res) do
        defs[#defs+1] = save_model_to_db(model, drop_existed_table)
    end
    return defs
end

local function main(models, drop_existed_table)
    models = models or get_models
    if type(models) == 'function' then
        models = models()
    elseif type(models) ~= 'table' then
        assert(nil, 'invalid argument, should be either a function or table.')
    end
    return save_models_to_db(models, drop_existed_table)
end


return {
    main = main,
    save_model_to_db = save_model_to_db,
    save_models_to_db = save_models_to_db,
}
    