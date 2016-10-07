local type = type
local pairs = pairs
local next = next
local ipairs = ipairs
local table_sort = table.sort
local table_concat = table.concat
local table_insert = table.insert
local string_format = string.format
local ngx_re_gsub = ngx.re.gsub
local ngx_re_match = ngx.re.match

local function map(tbl, func)
    local res = {}
    for i=1, #tbl do
        res[i] = func(tbl[i])
    end
    return res
end
local function string_strip(value)
    return ngx_re_gsub(value, [[^\s*(.+)\s*$]], '$1', 'jo')
end
local function is_empty_value(value)
    if value == nil or value == '' then
        return true
    elseif type(value) == 'table' then
        return next(value) == nil
    else
        return false
    end
end
local function to_html_attrs(tbl)
    local attrs = {}
    local boolean_attrs = {}
    for k, v in pairs(tbl) do
        if v == true then
            table_insert(boolean_attrs, ' '..k)
        elseif v then -- exclude false
            -- ignore the situation that v contains double quote
            table_insert(attrs, string_format(' %s="%s"', k, v))
        end
    end
    return table_concat(attrs, "")..table_concat(boolean_attrs, "")
end
local function list(...)
    local total = {}
    for i, t in next, {...}, nil do -- not `ipairs` in case of sparse {...}
        for i, v in ipairs(t) do
            total[#total+1] = v
        end
    end
    return total
end
local function dict(...)
    local total = {}
    for i, t in next, {...}, nil do
        for k, v in pairs(t) do
            total[k] = v
        end
    end
    return total
end
local function dict_update(t, ...)
    for i, d in next, {...}, nil do
        for k, v in pairs(d) do
            t[k] = v
        end
    end
    return t
end
local function list_extend(t, ...)
    for i, l in next, {...}, nil do 
        for i, v in ipairs(l) do
            t[#t+1] = v
        end
    end
    return t
end
local function reversed_metatables(self)
    local depth = 0
    local _self = self
    while true do
        _self = getmetatable(_self)
        if _self then
            depth = depth + 1
        else
            break
        end
    end
    local function iter()
        local _self = self
        for i = 1,  depth do
            _self = getmetatable(_self)
        end
        depth = depth -1
        if depth ~= -1 then
            return _self
        end
    end
    return iter
end
local function metatables(self)
    local function iter()
        local cls = getmetatable(self)
        self = cls
        return cls
    end
    return iter
end
local function table_has(t, e)
    for i, v in ipairs(t) do
        if v == e then
            return true
        end
    end
    return false
end
local function sorted(t, func)
    local keys = {}
    for k, v in pairs(t) do
        keys[#keys+1] = k
    end
    table_sort(keys, func)
    local i = 0
    return function ()
        i = i + 1
        key = keys[i]
        return key, t[key]
    end
end
local function curry(func, kwargs)
    local function _curry(morekwargs)
        return func(dict(kwargs, morekwargs))
    end
    return _curry
end
local function serialize_basetype(v)
    if type(v) == 'number' then
        return tostring(v)
    else
        return string_format("%q", v)
    end
end
local function _get_column_name(name, table_name)
    return name
    -- if name:find(' ', 1) then
    --     return name
    -- elseif table_name then
    --     return string_format("`%s`.`%s`", table_name, name)
    -- else
    --     return "`"..name.."`"
    -- end
end
local function serialize_columns(columns, table_name)
    -- convert a table named `foo` with columns like {'age', 'name'} 
    -- to string `foo`.`age`, `foo`.`name`
    local res = {}
    for i, v in ipairs(columns) do
        res[#res+1] = _get_column_name(v, table_name)
    end
    return table_concat(res, ", ")
end
local function serialize_attrs(attrs, table_name)
    -- {a=1, b='bar'} -> `foo`.`a` = 1, `foo`.`b` = "bar"
    local res = {}
    for k, v in pairs(attrs) do
        res[#res+1] = string_format('%s = %s', 
            string_format('`%s`.`%s`', table_name, k), serialize_basetype(v))
    end
    return table_concat(res, ", ")
end
local RELATIONS = {
    lt='%s < %s', lte='%s <= %s', gt='%s > %s', gte='%s >= %s', 
    ne='%s <> %s', eq='%s = %s', ['in']='%s IN %s', 
    exact = '%s = %s', iexact = '%s COLLATE UTF8_GENERAL_CI = %s',}
local STRING_LIKE_RELATIONS = {
    contains = '%s LIKE "%%%s%%"',
    icontains = '%s COLLATE UTF8_GENERAL_CI LIKE "%%%s%%"',
    startswith = '%s LIKE "%s%%"',
    istartswith = '%s COLLATE UTF8_GENERAL_CI LIKE "%s%%"',
    endswith = '%s LIKE "%%%s"',
    iendswith = '%s COLLATE UTF8_GENERAL_CI LIKE "%%%s"',
}

local function serialize_andkwargs(andkwargs, table_name)
    -- {age=23, id__in={1, 2, 3}, name='kat'} ->
    -- `foo`.`age` = 23 AND `foo`.`id` IN (1, 2, 3) AND `foo`.`name` = "kat"
    local results = {}
    for key, value in pairs(andkwargs) do
        -- try pattern `foo__bar` to split key
        local field, operator, template
        local pos = key:find('__', 1, true)
        if pos then
            field = key:sub(1, pos-1)
            operator = key:sub(pos+2)
        else
            field = key
            operator = 'exact'
        end
        template = RELATIONS[operator] or STRING_LIKE_RELATIONS[operator] or assert(nil, 'invalid operator:'..operator)
        if type(value) == 'string' then
            value = string_format("%q", value)
            if STRING_LIKE_RELATIONS[operator] then
                value = value:sub(2, -2)
                -- value = value:sub(2, -2):gsub([[\\]], [[\\\]]) --search for backslash, seems rare
            end
        elseif type(value) == 'table' then 
            -- turn table like {'a', 'b', 1} to string ('a', 'b', 1)
            local res = {}
            for i,v in ipairs(value) do
                res[i] = serialize_basetype(v)
            end
            value = '('..table_concat(res, ", ")..')'
        else -- number
            value = tostring(value)
        end
        results[#results+1] = string_format(template, _get_column_name(field, table_name), value)
    end
    return table_concat(results, " AND ")
end
local function split(s, sep)
    local i = 1
    local over = false
    local function _get()
        if over then
            return
        end
        local a, b = s:find(sep, i, true)
        if a then
            local e = s:sub(i, a-1)
            i = b + 1
            return e
        else
            e = s:sub(i)
            over = true
            return e
        end
    end
    return _get
end

return {
    dict = dict, 
    list = list, 
    table_has = table_has, 
    to_html_attrs = to_html_attrs, 
    string_strip = string_strip, 
    is_empty_value = is_empty_value, 
    dict_update = dict_update, 
    list_extend = list_extend, 
    reversed_metatables = reversed_metatables, 
    walk_metatables = walk_metatables, 
    sorted = sorted, 
    curry = curry, 
    serialize_basetype = serialize_basetype, 
    serialize_andkwargs = serialize_andkwargs, 
    serialize_attrs = serialize_attrs, 
    serialize_columns = serialize_columns, 
    map = map, 
    split = split, 
}

-- mysql> select * from user;
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- | id | update_time         | create_time         | passed | class | age | name     | score |
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- |  1 | 2016-09-25 18:51:48 | 2016-09-25 18:35:23 |      1 | 2     |  12 | kate'"\` |    60 |
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- 1 row in set (0.00 sec)

-- mysql> select * from user where name like "%\"%";
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- | id | update_time         | create_time         | passed | class | age | name     | score |
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- |  1 | 2016-09-25 18:51:48 | 2016-09-25 18:35:23 |      1 | 2     |  12 | kate'"\` |    60 |
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- 1 row in set (0.00 sec)

-- mysql> select * from user where name like "%'%";
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- | id | update_time         | create_time         | passed | class | age | name     | score |
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- |  1 | 2016-09-25 18:51:48 | 2016-09-25 18:35:23 |      1 | 2     |  12 | kate'"\` |    60 |
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- 1 row in set (0.00 sec)

-- mysql> select * from user where name like "%\\%";
-- Empty set (0.00 sec)

-- mysql> select * from user where name like "%\%";
-- Empty set (0.00 sec)

-- mysql> select * from user where name like "%\\\\%";
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- | id | update_time         | create_time         | passed | class | age | name     | score |
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- |  1 | 2016-09-25 18:51:48 | 2016-09-25 18:35:23 |      1 | 2     |  12 | kate'"\` |    60 |
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- 1 row in set (0.00 sec)

-- mysql> select * from user where name like "%\\\%";
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- | id | update_time         | create_time         | passed | class | age | name     | score |
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- |  1 | 2016-09-25 18:51:48 | 2016-09-25 18:35:23 |      1 | 2     |  12 | kate'"\` |    60 |
-- +----+---------------------+---------------------+--------+-------+-----+----------+-------+
-- 1 row in set (0.00 sec)