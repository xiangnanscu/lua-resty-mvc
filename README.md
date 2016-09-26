# lua-resty-mvc
**You don't need that complicated MVC framework!**
With just a plain folder with several simple files, you can enjoy basic but most frequently used MVC features.
# Quick start
try to start from `nginx -p . -c nginx.conf`, and visit [http://localhost:8080/init](http://localhost:8080/init)
# Api taste
Say you have a model named `Sale`.
```
Sale:select{'name', 'id'}:where'id=1'                               --get id=1 rows
Sale:where{id__lte=5}                                               --get id=1, 2, 3, 4, 5 rows
Sale:where{name='apple'}:where{time__gt='2016-03-11 23:59:00'}      -- `__gt` means `>`
Sale:where'catagory="fruit" and (weight>10 or price=8)':order'time' -- directly pass string for complicated query
Sale:select'name, count(*) as cnt':group'name':order'cnt desc'      -- group query
Sale:select'name, price*weight as value':order'value'               -- expression
Sale:select{'name', 'sum(weight*price) as value'}:group{'name'}:having{value__gte=200}:order'value desc'
```

# Synopsis
```
location = /register {
    content_by_lua_block{
        local UserForm = require"forms".UserForm
        local User = require"models".User
        local req = ngx.req
        local form;

        if req.get_method()=='POST' then
            req.read_body()
            form = UserForm:instance{data=req.get_post_args()}
            if form:is_valid() then
                local cd=form.cleaned_data
                local user, errors = User:instance(cd, true)
                if not user then
                    return ngx.print('Fail to create user, '..table.concat(errors, '<br/>'))
                else
                    return ngx.print(string.format(
                        'Congratulations! You have created a user successfully!'
                        ..'Name:%s, Password:%s, id:%s, now please try <a href="/login">login</a>', 
                        user.username, user.password, user.id))
                end
            end
        else
            form = UserForm:instance{}
        end
        local form_template=[[
<!DOCTYPE html>
<head>
  <title>lua-resty-mvc</title> 
</head>
<form method="post">
  %s
  <button type="submit">register</button>
</form>
</body>
</html>]]
                return ngx.print(string.format(form_template, form:render()))
            }
        }
```
# Todo
1. Foreign keys support
2. Auto create database table from Model if neccessary.
