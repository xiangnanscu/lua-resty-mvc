local encode = require"cjson".encode
local Model = require"resty.model".Model
local Query = require"resty.model".RawQuery

local Sale = Model:new{table_name='sales', 
    fields = {
        {name = 'id' }, 
        {name = 'name'}, 
        {name = 'catagory'}, 
        {name = 'price'}, 
        {name = 'weight'}, 
        {name = 'time'}, 
    }, 
}
local data = {
    {'apple',  'fruit',     8, 4,  '2016/3/3 12:22'}, 
    {'potato', 'vegetable', 3, 5,  '2016/3/4 8:02'}, 
    {'apple',  'fruit',     9, 2,  '2016/3/4 14:02'}, 
    {'orange', 'fruit',     6, 13, '2016/3/4 15:02'}, 
    {'potato', 'vegetable', 4, 4,  '2016/3/4 16:02'}, 
    {'pear',   'fruit',     8, 4,  '2016/3/5 15:12'}, 
    {'carrot', 'vegetable', 4, 3,  '2016/3/6 1:11'}, 
    {'orange', 'fruit',     6, 23, '2016/3/6 19:12'}, 
    {'grape',  'fruit',     8, 4,  '2016/3/6 9:12'}, 
    {'apple',  'fruit',     5, 9,  '2016/3/14 22:02'}, 
    {'grape',  'fruit',     5, 20, '2016/3/14 23:00'}, 
    {'tomato', 'vegetable', 8, 200,'2016/3/24 23:12'}, 
}
local res, err = Query("drop table if exists sales")
res, err = Query([[create table sales(
    id       serial primary key,
    name     varchar(10), 
    catagory varchar(15), 
    price    integer,  
    weight   float, 
    time     datetime);]]
)
if not res then
    return ngx.say(err)
end
for i,v in ipairs(data) do
    local name, catagory, price, weight, time  = unpack(v)
    res, err = Query(string.format(
        [[insert into sales(name, catagory, price, weight, time) values ('%s','%s', %s, %s, '%s');]],
        unpack(v)
    ))
    if not res then
        return ngx.say(err)
    end
end

local function has_error(codi, err)
    if not codi then
        return err
    else
        return nil
    end
end
local statements = {
    {Sale:where{}, 
        function(res)return has_error(#res==#data, 'total amount should equal'..#data)end}, 
    
    {Sale:select{'name', 'id'}:where'id=1', 
        function(res)return has_error(tonumber(res[1].id)==1, 'id should equal 1')end}, 
    
    {Sale:where{id__lte=5}, 
        function(res)return has_error(#res==5, 'the count of rows should be 5')end}, 
    
    {Sale:where{id=3}, 
        function(res)return has_error(tonumber(res[1].id)==3, 'id should equal 3')end}, 
    
    {Sale:where{name='apple'}:where{time__gt='2016-03-11 23:59:00'}, 
        function(res)return has_error(#res==1, 'should be only one row')end}, 
    
    {Sale:where'catagory="fruit" and (weight>10 or price=8)':order'time', 
        function(res)return has_error(#res==6, 'should return 6 rows')end},    
    
    {Sale:where{name='apple'}:order'price desc', 
        function(res)return has_error(#res==3, 'the count of apple rows should be 3')end}, 
    
    {Sale:select'name, count(*) as cnt':group'name':order'cnt desc', 
        function(res)return has_error(res[1].name=='apple', 'the amount of apple should be the most')end}, 
    
    {Sale:select'name, price*weight as value':order'value', 
        function(res)return has_error(res[1].name=='carrot', 'the value of carrot should be the least')end}, 
    
    {Sale:select'catagory, sum(weight) as total_weight':group'catagory':order'total_weight desc', 
        function(res)return has_error(res[1].catagory=='vegetable', 'the weight of vegetable should be the most')end}, 
    
    {Sale:select{'name', 'sum(weight*price) as value'}:group{'name'}:having{value__gte=200}:order'value desc', 
        function(res)return has_error(#res==2, 'there should only be two names that have revenue greater than 200')end}, 
}
local function print_results (res) 
    if res[1]~=nil then
        local columns = {}
        for k,v in pairs(res[1]) do
            columns[#columns+1] = k
        end
        ngx.say('<table>')
        ngx.say('<tr>')
        for i,col in ipairs(columns) do
            ngx.say( string.format('<th>%s</th>', col))
        end
        ngx.say('</tr>')
        for i,row in ipairs(res) do
            ngx.say('<tr>')
            for i,col in ipairs(columns) do
                ngx.say(string.format('<td>%s</td>', row[col]))
            end
            ngx.say('</tr>')
        end
        ngx.say('</table>')

    end
end
local function print_line(text, err)
    if err then
        ngx.say('<div style="color:red"> ERROR:', text, '</div>')
    else
        ngx.say('<div>', text, '</div>')
    end
end

ngx.say('<html><head><style>th,td{border:1px solid #ccc;}table{border-collapse:collapse;}</style></head><body>')
for i,v in ipairs(statements) do
    local statement, check_error = unpack(v)
    local res, err, errno, sqlstate = statement:exec()
    if res~=nil then --sql returned normally
        err = check_error(res)
        if err then
            print_line(statement:to_sql(), 1)
            print_line(err, 1)
        else
            print_line(statement:to_sql())           
        end
        print_results(res)  
    else --something wrong with sql
        print_line(statement:to_sql(), 1)
        print_line(err, 1)
    end
    ngx.say('<br/>')
end
--update test
local statement=Sale:where'id<3'
for i,v in ipairs(statement:exec()) do
    v.blablabla = 123 --attribute that is not in fields
    v.price=10+i
    v:save()
end
for i,v in ipairs(statement:exec()) do
    assert(v.price==10+i, 'price update should take effect')
end
print_line(statement:to_sql())
print_results(statement:exec())

--create test
v = Sale:create{name='newcomer', catagory='fruit', time='2016-03-29 23:12:00', price=12, weight=15}
local res = Sale:all()
assert(res[#res].name==v.name, 'the name of the last element should be newcomer')

--delete test
local v = Sale:get'id = 1'
v:delete()
assert(#Sale:where"id=1":exec()==0, 'id=1 item should not exists')

ngx.say('<h1>all test passed!</h1>')
ngx.say('</body></html>')