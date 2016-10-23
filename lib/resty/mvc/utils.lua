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

local is_windows = package.config:sub(1,1) == '\\'

local function map(tbl, func)
    local res = {}
    for i=1, #tbl do
        res[i] = func(tbl[i])
    end
    return res
end
local function filter(tbl, func)
    local res = {}
    for i=1, #tbl do
        local v = tbl[i]
        if func(v) then
            res[#res+1] = v
        end
    end
    return res
end
local function list(...)
    local total = {}
    -- t should not be a sparse table
    for _, t in next, {...} do
        for i = 1, #t do
            total[#total+1] = t[i]
        end
    end
    return total
end
local function list_extend(t, ...)
    for _, a in next, {...} do 
        for i = 1, #a do
            t[#t+1] = a[i]
        end
    end
    return t
end
local function list_has(t, e)
    for i, v in ipairs(t) do
        if v == e then
            return true
        end
    end
    return false
end
local function dict(...)
    local total = {}
    for i, t in next, {...} do
        for k, v in pairs(t) do
            total[k] = v
        end
    end
    return total
end
local function dict_update(t, ...)
    for i, d in next, {...} do
        for k, v in pairs(d) do
            t[k] = v
        end
    end
    return t
end
local function dict_has(t, e)
    for k, v in pairs(t) do
        if v == e then
            return true
        end
    end
    return false
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
local function reversed_inherited_chain(self)
    local res = {self}
    local cls = getmetatable(self)
    while cls do
        table.insert(res, 1, cls)
        self = cls
        cls = getmetatable(self)
    end
    return res
end
local function inherited_chain(self)
    local res = {self}
    local cls = getmetatable(self)
    while cls do
        res[#res+1] = cls
        self = cls
        cls = getmetatable(self)
    end
    return res
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
    if type(v) == 'string' then
        return string_format("%q", v)
    else
        return tostring(v)
    end
end
local function serialize_attrs(attrs, table_name)
    -- {a=1, b='bar'} -> `foo`.`a` = 1, `foo`.`b` = "bar"
    -- {a=1, b='bar'} -> a = 1, b = "bar"
    local res = {}
    if table_name then
        for k, v in pairs(attrs) do
            k = string_format('`%s`.`%s`', table_name, k)
            res[#res+1] = string_format('%s = %s', k, serialize_basetype(v))
        end
    else
        for k, v in pairs(attrs) do
            res[#res+1] = string_format('%s = %s', k, serialize_basetype(v))
        end
    end
    return table_concat(res, ", ")
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
local function cache_result(f)
    local result
    local function _cache(...)
        if not result then
            result = f(...)
        end
        return result
    end
    return _cache
end
local dd = {s=1, m=60, h=3600, d=3600*24, w=3600*24*7, M=3600*24*30, y=3600*24*365}
local function time_parser(t)
    if type(t) == 'string' then
        local unit = string.sub(t,-1,-1)
        local secs = dd[unit]
        if not secs then
            assert(nil, 'invalid time unit: '..unit)
        end
        local ts = string.sub(t, 1, -2)
        local num = tonumber(ts)
        if not num then
            assert(nil, "can't convert `"..ts.."` to a number")
        end        
        return num * secs
    elseif type(t) == 'number' then
        return t
    else
        assert(false, 'you should provide either a string or number as a time')
    end
end

local get_dirs
if is_windows then
    function get_dirs(directory)
        local t, popen = {}, io.popen
        local pfile = popen('dir "'..directory..'" /b /ad')
        for filename in pfile:lines() do
            if not filename:find('__') then
                t[#t+1] = filename
            end
        end
        pfile:close()
        return t
    end
else
    function get_dirs(directory)
        local t = {}
        local pfile = io.popen('ls -l "'..directory..'" | grep ^d')
        for filename in pfile:lines() do
            t[#t+1] = filename:match('%d%d:%d%d (.+)$')
        end
        pfile:close()
        return t
    end
end
local Lazy = {}
Lazy.__index = function (t, k)
    if not t.__object then
        t.__object = t.__func()
    end
    return t.__object[k]
end 
Lazy.__newindex = function (t, k, v)
    if not t.__object then
        t.__object = t.__func()
    end
    t.__object[k] = v
end 
Lazy.__pairs = function (t)
    if not t.__object then
        t.__object = t.__func()
    end
    return pairs(t.__object)
end
Lazy.__ipairs = function (t)
    if not t.__object then
        t.__object = t.__func()
    end
    return ipairs(t.__object)
end
Lazy.__call = function (t, ...)
    if not t.__object then
        t.__object = t.__func()
    end
    return t.__object(...)
end
Lazy.__tostring = function (t)
    if not t.__object then
        t.__object = t.__func()
    end
    return tostring(t.__object)
end
Lazy.__eq = function (t, o)
    if not t.__object then
        t.__object = t.__func()
    end
    return t.__object == o
end
Lazy.__lt = function (t, o)
    if not t.__object then
        t.__object = t.__func()
    end
    return t.__object < o
end
Lazy.__le = function (t, o)
    if not t.__object then
        t.__object = t.__func()
    end
    return t.__object <= o
end
Lazy.__unm = function (t)
    if not t.__object then
        t.__object = t.__func()
    end
    return -t.__object
end
Lazy.__add = function (t, o)
    if not t.__object then
        t.__object = t.__func()
    end
    return t.__object + o
end
Lazy.__sub = function (t, o)
    if not t.__object then
        t.__object = t.__func()
    end
    return t.__object - o
end
Lazy.__mul = function (t, o)
    if not t.__object then
        t.__object = t.__func()
    end
    return t.__object * o
end
Lazy.__div = function (t, o)
    if not t.__object then
        t.__object = t.__func()
    end
    return t.__object / o
end
Lazy.__mod = function (t, o)
    if not t.__object then
        t.__object = t.__func()
    end
    return t.__object % o
end
Lazy.__pow = function (t, o)
    if not t.__object then
        t.__object = t.__func()
    end
    return t.__object ^ o
end
Lazy.__concat = function (t, o)
    if not t.__object then
        t.__object = t.__func()
    end
    return t.__object .. o
end
function Lazy.new(cls, func)
    local self = {}
    self.__func = func
    self.__object = false
    self.__pairs = cls.__pairs
    self.__ipairs = cls.__ipairs
    return setmetatable(self, cls)
end
return {
    map = map, 
    filter = filter,
    dict = dict, 
    list = list, 
    dict_has = dict_has,
    list_has = list_has,
    table_has = table_has, 
    to_html_attrs = to_html_attrs, 
    string_strip = string_strip, 
    is_empty_value = is_empty_value, 
    dict_update = dict_update, 
    list_extend = list_extend, 
    reversed_inherited_chain = reversed_inherited_chain, 
    inherited_chain = inherited_chain, 
    sorted = sorted, 
    curry = curry, 
    serialize_basetype = serialize_basetype, 
    serialize_andkwargs = serialize_andkwargs, 
    serialize_attrs = serialize_attrs, 
    split = split, 
    cache_result = cache_result,
    time_parser = time_parser,
    get_dirs = get_dirs,
    Lazy = Lazy,
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