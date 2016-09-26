local encode = require"cjson".encode
local Model = require"resty.mvc.model"
local Query = require"resty.mvc.query".single
local Field = require"resty.mvc.modelfield"

local M = {}
local function sametable(a, b)
    for k,v in pairs(a) do
        if type(b[k])~=type(v) then
            return
        end
        if type(v)=='table' then
            if not sametable(b[k],v) then
                return
            end
        else
            if b[k]~=v then
                return
            end
        end
    end
    for k,v in pairs(b) do
        if type(a[k])~=type(v) then
            return
        end
        if type(v)=='table' then
            if not sametable(a[k],v) then
                return
            end
        else
            if a[k]~=v then
                return
            end
        end
    end
    return true
end
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
local Sale = Model:class{table_name='sales', 
    fields = {
        id = Field.IntegerField{ min=1}, 
        name = Field.CharField{ maxlen=50},
        catagory = Field.CharField{maxlen=15},  
        price = Field.IntegerField{ min=0}, 
        weight = Field.IntegerField{ min=1}, 
        time = Field.CharField{ maxlen=50}, 
    }, 
}
M[#M+1]=function ()
    local res, err = Query("drop table if exists sales")
    if not res then
        return err
    end
    res, err = Query([[create table sales(
        id       serial primary key,
        name     varchar(50), 
        catagory varchar(15), 
        price    integer,  
        weight   float, 
        time     datetime);]])
    if not res then
        return err
    end
    for i,v in ipairs(data) do
        local ins = Sale:instance{name=v[1], catagory=v[2], price=v[3], weight=v[4], time=v[5]}
        local res, err = ins:create()
        if not res then
            return err
        end
    end
end

M[#M+1]=function( ... )
    local a = Sale:all()
    local b = Sale:all()
    if not sametable(a, b) then
        return 'the table returned from `-Sale:where{}` doesnot equal the one from `Sale:all()`'
    end
    if #a ~= #data then 
        return '`Sale:all()` doesnot return all objects'
    end
end
M[#M+1]=function (self)
    local res, err = Sale:select{'name', 'id'}:where'id=1':exec()
    if not res then
        return err
    end
    if #res ~= 1 then
        return 'should return only one row, but get '..#res
    end
    local obj = res[1]
    if type(obj)~='table' then
        return 'select clause should return a table'
    end
    for k,v in pairs(obj) do
        if k~='name' and k~='id' then
            return 'key `'..k..'` should not exists'
        end
    end
    if obj.id ~= '1' then
        return 'id doesnot equal 1'
    end
end

M[#M+1]=function(self)
    local res = Sale:where{id__lte=5}:exec()
    if #res~=5 then
        return 'the count of rows should be 5'
    end
    local res = Sale:where{id__lt=5}:exec()
    if #res~=4 then
        return 'the count of rows should be 4'
    end
end
M[#M+1]=function(self)
    local res = Sale:where{name='apple'}:where{time__gt='2016-03-11 23:59:00'}:exec()
    if #res~=1 then
        return 'the count of rows should be 1'
    end
end
M[#M+1]=function(self)
    local res = Sale:where'catagory="fruit" and (weight>10 or price=8)':order'time':exec()
    if #res~=6 then
        return 'the count of rows should be 6'
    end
end
M[#M+1]=function(self)
    local res, err = Sale:select'name, count(*) as cnt':group'name':order'cnt desc':exec()
    if not res then
        return err
    end
    if res[1].name~='apple' then
        return 'the amount of apple should be the most'
    end
end
M[#M+1]=function(self)
    local res = Sale:select'name, price*weight as value':order'value':exec()
    if res[1].name~='carrot' then
        return 'the value of carrot should be the least'
    end
end
M[#M+1]=function(self)
    local res = Sale:select'catagory, sum(weight) as total_weight':group'catagory':order'total_weight desc':exec()
    if res[1].catagory~='vegetable' then
        return 'the weight of vegetable should be the most'
    end
end
M[#M+1]=function(self)
    local res, err = Sale:select{'name', 'sum(weight*price) as value'}:group{'name'}:having{value__gte=200}:order'value desc':exec()
    if not res then
        return err
    end
    if #res~=2 then
        return 'there should only be two names that have revenue greater than 200'
    end
end
M[#M+1]=function(self)
    --update test
    local statement=Sale:where'id<5'
    for i,v in ipairs(statement:exec()) do
        v.blaaa = 'sdfd'
        v.blablabla = 123 --attribute that is not in fields
        v.price=10+i
        v:update()
    end
    for i,v in ipairs(statement:exec()) do
        if v.price~=10+i then
            return 'price update doesnot work as expected'
        end
    end
    --create test
    local v = Sale:instance{name='newcomer', catagory='fruit', time='2016-03-29 23:12:00', price=12, weight=15}
    v:create()
    local res = Sale:all()
    if res[#res].name~=v.name then
        return 'the name of the last element should be newcomer'
    end
    v.catagory='wwwww'
    v:update()
    v=Sale:get{name='newcomer'}
    if v.catagory~='wwwww' then 
        return 'the catagory of the last element should be wwwww'
    end
    v = Sale:get'catagory = "wwwww"'
    v.price=-2
    local res,errs=v:update()
    if errs==nil then
        return 'should be some errors.'
    end
    v:delete()
    if #Sale:where"catagory = 'wwwww'":exec()~=0 then
        return 'delete clause doesnot work. '
    end
    v = Sale:instance{name='newcomer2', catagory='fruit', time='2016-03-29 23:12:00', price=12, weight=150}
    v:create()
    v = Sale:get{name='newcomer2'}
    if v.weight~=150 then
        return 'newcomer2 weight should be 150'
    end
end
return M

    


