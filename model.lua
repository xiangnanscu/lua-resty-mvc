local DATABASES ={
    default = {
        engine = "resty.mysql", 
        host = "127.0.0.1", 
        port = 3306, 
        database = "test", 
        user = 'root', 
        password = '', 
        timeout = 1000, 
        pool_size = 800, 
        max_idle_timeout = 10000, 
    }, 
    postgresql = {
        engine = "resty.postgres", 
        host = "127.0.0.1", 
        port = 5432, 
        database = "postgres", 
        user = 'postgres', 
        password = '123', 
        timeout = 1000, 
        pool_size = 800, 
        max_idle_timeout = 10000, 
    }
}

--helper functions
local function copy(old)
    local res = {};
    for i,v in pairs(old) do
        if type(v) == "table" and v ~= old then
            res[i] = copy(v)
        else
            res[i] = v;
        end
    end
    return res;
end
local function update(self, other)
    for i,v in pairs(other) do
        if type(v) == "table" then
            self[i] = copy(v);
        else
            self[i] = v;
        end
    end
    return self
end
local function extend(self, other)
    for i,v in ipairs(other) do
        self[#self+1] = v
    end
    return self
end
local function log( ... )
    ngx.log(ngx.ERR, string.format('\n*************************************\n%s\n*************************************', table.concat({...}, "~~")))
end
local RELATIONS= {lt='<', lte='<=', gt='>', gte='>=', ne='<>', eq='=', ['in']='IN'}
local function parse_filter_args(kwargs)
    -- turn a hash table such as {age=23, id__in={1, 2, 3}} to a string array:
    -- {'age = 23', 'id IN (1, 2, 3)'}
    local conditions = {}
    for key, value in pairs(kwargs) do
        -- split string like 'age__lt' to 'age' and 'lt'
        local capture = string.gmatch(key, '%w+')
        local field, operator = capture(), capture()
        if operator == nil then
            operator = '='
        else
            operator = RELATIONS[operator] or '='
        end
        if type(value) == 'string' then
            value = string.format([['%s']], value)
        elseif type(value) == 'table' then 
            -- such as: SELECT * FROM user WHERE name in ('a', 'b', 'c');
            local res = {}
            for i,v in ipairs(value) do
                if type(v) == 'string' then
                    res[i] = string.format([['%s']], v)
                else
                    res[i] = tostring(v)
                end
            end
            value = '('..table.concat( res, ", ")..')'
        else
            value = tostring(value)
        end
        conditions[#conditions+1] = string.format(' %s %s %s ', field, operator, value)
    end
    return conditions
end

local function RawQuery(statement, using)
    local res, err, errno, sqlstate;
    local database = DATABASES[using or 'default']
    local db, err = require(database.engine):new()
    if not db then
        return db, err
    end
    db:set_timeout(database.timeout) 
    res, err, errno, sqlstate = db:connect{database = database.database,
        host = database.host, port = database.port,
        user = database.user, password = database.password,
    }
    if not res then
        return res, err, errno, sqlstate
    end
    res, err, errno, sqlstate =  db:query(statement)
    if res ~= nil then
        local ok, err = db:set_keepalive(database.max_idle_timeout, database.pool_size)
        if not ok then
            ngx.log(ngx.ERR, 'fail to set_keepalive')
        end
    end
    return res, err, errno, sqlstate
end

local Row = {}
function Row.new(self, attrs)
    -- requires a attribute called `QueryManager` that's derived from QueryManager
    attrs = attrs or {}
    setmetatable(attrs, self)
    self.__index = self
    return attrs
end
function Row.save(self)
    local valid_attrs = {}
    for i,field in ipairs(self.QueryManager.fields) do
        local value = self[field.name]
        if value ~= nil then
            valid_attrs[field.name] = value
        end
    end
    local res, err = self.QueryManager:new{}:update(valid_attrs):where{id=self.id}:exec()
    self._res, self._err = res, err
    return self
end
function Row.delete(self)
    local res, err = self.QueryManager:new{}:delete{id=self.id}:exec()
    return res, err
end

local QueryManager = {}
local sql_method_names = {select=extend, group=extend, order=extend,
    create=update, update=update, where=update, having=update, delete=update,}
-- add methods by a loop    
for method_name, processor in pairs(sql_method_names) do
    QueryManager[method_name] = function(self, params)
        if type(params) == 'table' then
            processor(self['_'..method_name], params)
        else
            self['_'..method_name..'_string'] = params
        end 
        return self
    end
end
function QueryManager.new(self, subclass)
    subclass = subclass or {}
    setmetatable(subclass, self)
    self.__index = self
    -- a shortcut for execute the statement
    self.__unm = function (t) return t:exec() end
    subclass.Row = Row:new{QueryManager = subclass}
    return subclass:init()
end
function QueryManager.init(self)
    for method_name, _ in pairs(sql_method_names) do
        self['_'..method_name] = {}
    end
    return self
end
function QueryManager.to_sql(self)
    if next(self._update)~=nil or self._update_string~=nil then
        return self:to_sql_update()
    elseif next(self._create)~=nil or self._create_string~=nil then
        return self:to_sql_create()     
    elseif next(self._delete)~=nil or self._delete_string~=nil then
        return self:to_sql_delete()
    else -- q:select or q:get
        return self:to_sql_select() 
    end
end
function QueryManager.to_sql_update(self)
    --UPDATE 表名称 SET 列名称 = 新值 WHERE 列名称 = 某值
    return string.format('UPDATE %s SET %s%s;', self.table_name, 
        self:get_update_args(), self:get_where_args())
end
function QueryManager.to_sql_create(self)
    local create_columns, create_values = self:get_create_args()
    return string.format('INSERT INTO %s (%s) VALUES (%s);', self.table_name, 
        create_columns, create_values)
end
function QueryManager.to_sql_delete(self)
    --UPDATE 表名称 SET 列名称 = 新值 WHERE 列名称 = 某值
    local where_args = self:get_delete_args()
    if where_args == '' then
        return nil, 'where clause must be provided for delete statement'
    end
    return string.format('DELETE FROM %s%s;', self.table_name, where_args)
end
function QueryManager.get_create_args(self)
    local cols = {}
    local vals = {}
    for k,v in pairs(self._create) do
        cols[#cols+1] = k
        if type(v) == 'string' then
            v = string.format([['%s']], v)
        else
            v = tostring(v)
        end
        vals[#vals+1] = v
    end
    return table.concat( cols, ", "), table.concat( vals, ", ")
end

function QueryManager.get_update_args(self)
    if next(self._update)~=nil then 
        return table.concat(parse_filter_args(self._update), ", ")
    elseif self._update_string ~= nil then
        return self._update_string
    else
        return ''
    end
end
function QueryManager.get_where_args(self)
    if next(self._where)~=nil then 
        return ' WHERE '..table.concat(parse_filter_args(self._where), " AND ")
    elseif self._where_string ~= nil then
        return ' WHERE '..self._where_string
    else
        return ''
    end
end
function QueryManager.get_delete_args(self)
    if next(self._delete)~=nil then 
        return ' WHERE '..table.concat(parse_filter_args(self._delete), " AND ")
    elseif self._delete_string ~= nil then
        return ' WHERE '..self._delete_string
    else
        return ''
    end
end
function QueryManager.get_having_args(self)
    if next(self._having)~=nil then 
        return ' HAVING '..table.concat(parse_filter_args(self._having), " AND ")
    elseif self._having_string ~= nil then
        return ' HAVING '..self._having_string
    else
        return ''
    end
end
function QueryManager.get_order_args(self)
    if next(self._order)~=nil then 
        return ' ORDER BY '..table.concat(self._order, ", ")
    elseif self._order_string ~= nil then
        return ' ORDER BY '..self._order_string
    else
        return ''
    end  
end
function QueryManager.get_group_args(self)
    if next(self._group)~=nil then 
        return ' GROUP BY '..table.concat(self._group, ", ")
    elseif self._group_string ~= nil then
        return ' GROUP BY '..self._group_string
    else
        return ''
    end  
end
function QueryManager.get_select_args(self)
    if next(self._select)~=nil  then
        return table.concat(self._select, ", ")
    elseif self._select_string ~= nil then
        return self._select_string
    else
        return '*'
    end  
end
function QueryManager.to_sql_select(self)
    --SELECT..FROM..WHERE..GROUP BY..HAVING..ORDER BY
    local statement = 'SELECT %s FROM %s%s%s%s%s;'
    local select_args = self:get_select_args()
    local where_args = self:get_where_args()
    local group_args = self:get_group_args()
    local having_args = self:get_having_args()
    local order_args = self:get_order_args()
    return string.format(statement, select_args, self.table_name, where_args, 
        group_args, having_args, order_args)
end
function QueryManager.get(self, params)
    -- special process for get
    if type(params) == 'table' then
        update(self._where, params)
    else
        self['_where_string'] = params
    end 
    local where_args = self:get_where_args()
    if where_args == '' then
        return nil, 'filter arguments must be provied'
    end  
    local statement = string.format('SELECT * FROM %s%s;', self.table_name, where_args)
    local res, err = RawQuery(statement)
    if not res then
        return res, err
    end
    if #res ~= 1 then
        return nil, 'result count must equal 1'
    end
    return self.Row:new(res[1])
end
function QueryManager.exec_raw(self)
    local statement, err = self:to_sql()
    if not statement then
        return nil, err
    end
    return RawQuery(statement)
end
    -- insert_id   0   number --0代表是update 或 delete
    -- server_status   2   number
    -- warning_count   0   number
    -- affected_rows   1   number
    -- message   (Rows matched: 1  Changed: 0  Warnings: 0   string

    -- insert_id   1006   number --大于0代表成功的insert
    -- server_status   2   number
    -- warning_count   0   number
    -- affected_rows   1   number
function QueryManager.exec(self)
    local statement, err = self:to_sql()
    if not statement then
        return nil, err
    end
    local res, err = RawQuery(statement)
    if not res then
        return res, err
    end
    local altered = res.insert_id
    if altered ~= nil then
        -- update or delete or insert
        if altered > 0 then --insert
            return self.Row:new(extend({id = altered}, self._create))
        else --update or delete
            return res
        end
    elseif (next(self._group) == nil and self._group_string == nil and
            next(self._having) == nil and self._having_string == nil ) then
        -- wrapp the result only for non-aggregation query.
        local wrapped_res = {} 
        local _meta = {table_name=self.table_name, fields=self.fields}
        for i, attrs in ipairs(res) do
            wrapped_res[i] = self.Row:new(attrs)
        end
        return wrapped_res
    else
        return res
    end
end

local Model = {}
function Model.new(self, subclass)
    subclass = subclass or {}
    setmetatable(subclass, self)
    self.__index = self
    subclass.QueryManager = QueryManager:new{table_name=subclass.table_name, 
        fields=subclass.fields}
    return subclass
end
function Model._proxy_sql(self, method, params)
    local subclass = self.QueryManager:new{}
    return subclass[method](subclass, params)
end
for method_name, func in pairs(sql_method_names) do
    Model[method_name] = function(self, params)
        return self:_proxy_sql(method_name, params)
    end
end
function Model.get(self, params)
    -- special process for get
    return self:_proxy_sql('get', params)
end

return {Model = Model, RawQuery = RawQuery, QueryManager = QueryManager}