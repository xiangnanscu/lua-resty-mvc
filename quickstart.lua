local Model = require"resty.model".Model
local Query = require"resty.model".RawQuery

local res, err = Query("drop table if exists users")
res, err = Query([[create table users(
    id       serial primary key,
    name     varchar(10), 
    email    varchar(50), 
    phone    varchar(11));]]
)
if not res then
    return ngx.say(err)
end
local User = Model:new{
    table_name = 'users', 
    fields     = {
        {name = 'id' }, 
        {name = 'name'}, 
        {name = 'email'}, 
        {name = 'phone'}, 
    }, 
}
--create a user in the database and return a user object which you can read or modify later.
local user = User:create{name='Kate', email='abc@qq.com', phone='13355556666'}
-- update the return user object 
user.name = 'Tom'
user:save()
-- read 
user = User:get{id=user.id}
--update
user.phone = '18899996666'  
user:save()
--delete
user:delete() 
--return all user
res = User:all()
--find all user whose name is `Tom` and id is greater than 5 in three ways.
res = User:where{name='Tom', id__gt=5}:exec()
res = User:where{name='Tom'}:where{id__gt=5}:exec()
res = User:where"name='Tom' and id>5":exec()
--group
res = User:select'name, count(*) as cnt':group'name':exec()
res = User:select{'id', 'name'}:where"id<10 and (name like 'K%' or name like '%g')":order'name desc':exec()