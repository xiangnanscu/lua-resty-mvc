local client = require"resty.mysql"

local CONNECT_TABLE = {host = "127.0.0.1", port = 3306, 
        database = "test", user = 'root', password = '', }
local CONNECT_TIMEOUT = 1000
local IDLE_TIMEOUT = 10000
local POOL_SIZE = 800

local function query(statement, rows)
    local db, err = client:new()
    if not db then
        return nil, err
    end
    db:set_timeout(CONNECT_TIMEOUT) 
    local res, err, errno, sqlstate = db:connect(CONNECT_TABLE)
    if not res then
        return nil, err, errno, sqlstate
    end
    res, err, errno, sqlstate =  db:query(statement, rows)
    if res ~= nil then
        local ok, err = db:set_keepalive(IDLE_TIMEOUT, POOL_SIZE)
        if not ok then
            return nil, err
        end
    end
    return res, err, errno, sqlstate
end

local function multiple_query(statements)
    local db, err = client:new()
    if not db then
        return nil, err
    end
    db:set_timeout(CONNECT_TIMEOUT) 
    local res, err, errno, sqlstate = db:connect(CONNECT_TABLE)
    if not res then
        return nil, err, errno, sqlstate
    end
    local bytes, err = db:send_query(statements)
    if not bytes then
        return nil, "failed to send query: " .. err
    end

    local i = 0
    local over = false
    return function()
        if over then return end
        i = i + 1
        res, err, errcode, sqlstate = db:read_result()
        if not res then
            -- according to official docs, further actions should stop if any error occurs
            over = true
            return nil, string.format('bad result #%s: %s', i, err), errcode, sqlstate
        else
            if err ~= 'again' then
                over = true
                local ok, err = db:set_keepalive(IDLE_TIMEOUT, POOL_SIZE)
                if not ok then
                    return nil, err
                end
            end
            return res
        end
    end
end

local function update(self, other)
    for i, v in pairs(other) do
        self[i] = v
    end
    return self
end
local function extend(self, other)
    for i, v in ipairs(other) do
        self[#self+1] = v
    end
    return self
end
local function caller(t, opts) 
    return t:new(opts):initialize() 
end
local function execer(t) 
    return t:exec() 
end
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR


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

local function _get_insert_args(t)
    local cols = {}
    local vals = {}
    for k,v in pairs(t) do
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

local Row = {}
function Row.new(self, opts)
    -- opts should be something like {table_name='foo', fields={...}}
    opts = opts or {}
    self.__index = self
    return setmetatable(opts, self)
end
function Row.save(self)
    local valid_attrs = {}
    local all_errors = {}
    local errors;
    for name, field in pairs(self.fields) do
        local value = rawget(self, name)
        if value ~= nil then
            value, errors = field:clean(value)
            if errors then
                extend(all_errors, errors)
            else
                valid_attrs[name] = value
            end
        end
    end
    if next(all_errors) then
        return nil, all_errors
    end
    if rawget(self, 'id') then
        return query(string.format('UPDATE %s SET %s WHERE id=%s;', 
            self.table_name, table.concat(parse_filter_args(valid_attrs), ", "), self.id))
    else
        local create_columns, create_values = _get_insert_args(valid_attrs)
        return query(string.format('INSERT INTO %s (%s) VALUES (%s);', 
            self.table_name, create_columns, create_values))
    end
end
function Row.delete(self)
    return query(string.format('DELETE FROM %s WHERE id=%s;', self.table_name, self.id))
end

local QueryManager = setmetatable({}, {__call = caller})
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
function QueryManager.new(self, opts)
    opts = opts or {}
    self.__index = self
    self.__call = caller
    self.__unm = execer
    return setmetatable(opts, self)
end
function QueryManager.initialize(self)
    for method_name, _ in pairs(sql_method_names) do
        self['_'..method_name] = {}
    end
    self.Row = Row:new{table_name=self.table_name, fields=self.fields}
    return self
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
    local res, err = query(statement)
    if not res then
        return nil, err
    end
    local altered = res.insert_id
    if altered ~= nil then -- update or delete or insert
        if altered > 0 then --insert
            return self.Row:new(update({id = altered}, self._create))
        else --update or delete
            return res
        end
    elseif (next(self._group) == nil and self._group_string == nil and
            next(self._having) == nil and self._having_string == nil ) then
        for i, attrs in ipairs(res) do
            res[i] = self.Row:new(attrs)
        end
        return res
    else
        return res
    end
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
    return _get_insert_args(self._create)
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
function QueryManager.exec_raw(self)
    local statement, err = self:to_sql()
    if not statement then
        return nil, err
    end
    return query(statement)
end

local Model = {}
local function model_caller(self, attrs)
    return Row:new{table_name=self.table_name,fields=self.fields}:new(attrs)
end
function Model.new(self, opts)
    opts = opts or {}
    self.__index = self
    self.__call = model_caller
    return setmetatable(opts, self)
end
function Model._resolve_fields(self)
    local fields = self.fields
    if self.field_order == nil then
        local fo = {}
        for name,v in pairs(fields) do
            fo[#fo+1] = name
        end
        self.field_order = fo
    end
    for name, field_maker in pairs(fields) do
        fields[name] = field_maker{name=name}
    end
    return self
end
function Model.make(self, init)
    return self:new(init):_resolve_fields()
end
function Model._proxy_sql(self, method, params)
    local qm = QueryManager{table_name=self.table_name, fields=self.fields}
    return qm[method](qm, params)
end
-- define methods by a loop, `create` will be override
for method_name, func in pairs(sql_method_names) do
    Model[method_name] = function(self, params)
        return self:_proxy_sql(method_name, params)
    end
end
function Model.get(self, params)
    -- special process for `get`
    local res, err = self:_proxy_sql('where', params):exec()
    if not res then
        return nil, err
    end
    if #res ~= 1 then
        return nil, '`get` method should return only one row'
    end
    return res[1]
end
function Model.all(self)
    -- special process for `all`
    return self:_proxy_sql('where', {}):exec()
end
function Model.create(self, params)
    -- special process for `create`
    return self:_proxy_sql('create', params):exec()
end
return {Model = Model, QueryManager = QueryManager, query = query, multiple_query=multiple_query, }