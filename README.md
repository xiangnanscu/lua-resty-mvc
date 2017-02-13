# lua-resty-mvc
**You don't need that complicated MVC framework!**
With just a plain folder with several simple files, you can enjoy basic but most frequently used MVC features.
# Dependencies
[lua-resty-mysql](https://github.com/openresty/lua-resty-mysql)

[lua-resty-reqargs](https://github.com/bungle/lua-resty-reqargs)
# Quick start
Config your database in `lib/resty/mvc/query.lua` and try to start from `nginx -p . -c nginx.conf`, and visit [http://localhost:8080/init](http://localhost:8080/init)
# Api taste
Below is five models representing five database tables. Why so many tables?  Because I want to show you how powerful
the MVC is.
## Model relations 
|Model_name|col_1|col_2|col_3|col_4|col_5|
|---|---|---|---|---|---|
|Moreinfo|weight|height||||
|Detail|sex|age|info::Moreinfo|||
|User|name|money|detail::Detail|||
|Product|name|price||||
|Record|buyer::User|seller::User|product::Product|count|time|
symbol `::` means a foreign key relation
##Api example
if you're curious, please run this project and visit [http://localhost:8080/test](http://localhost:8080/test) to see
what are the final SQL statement.
```
User:where()
User:where{}
User:where{id=1}
User:where{id__gt=2}
User:where{id__in={1, 2, 3}}
User:where{name='kate'}
User:where{name__endswith='e'}
User:where{name__contains='a'}
User:where{id=1, name='kate'}
User:where{id=1}:where{name='kate'}
User:where{id__lt=3, name__startswith='k'}

User:where{Q{id__gt=2}}
User:where{Q{id__gt=2}, Q{id__lt=5}}
User:where{Q{id__gt=2, id__lt=5}}
User:where{Q{id__gt=2, id__lt=5}}:where{Q{name__startswith='k'}}
User:where{Q{id__gt=2, id__lt=5}}:where{name__startswith='k'}
User:where{Q{id__gt=2}/Q{id__lt=5}*Q{name__startswith='k'}}
User:where{Q{id__gt=2}/Q{id__lt=5}, name__startswith='k'}


Record:where{buyer=1}
Record:where{buyer__gt=1}
Record:where{buyer__in={1, 2}}
Record:where{buyer__name='kate'}
Record:where{buyer__name__startswith='k'}
Record:where{Q{buyer__name__startswith='k'}/Q{buyer__money__gt=100.2}}
Record:where{Q{buyer__name__startswith='k'}/Q{seller__money__gt=100.2}/Q{product__price__lt=50}}

Record:where{buyer=1}:join{'buyer'}
Record:where{buyer=1}:join{'seller'}
Record:where{buyer=1}:join{'buyer', 'seller'}
Record:where{buyer=1}:join{'buyer', 'seller', 'product'}

Record:where{seller__detail=1}
Record:where{seller__detail__lt=1}
Record:where{seller__detail__in={1, 2, 3}}
Record:where{seller__detail__sex='w'}
Record:where{seller__detail__age=20}
Record:where{seller__detail__age__gt=20}
Record:where{seller__detail__info=2}
Record:where{seller__detail__info__lt=2}
Record:where{seller__detail__info__in={1, 2}}
Record:where{seller__detail__info__weight=55}
Record:where{seller__detail__info__weight__gt=55}
Record:where{seller__detail__info__weight__in={45, 55}}

Record:where{Q{buyer__detail__age__gt=20}/Q{seller__detail__age__gt=20}}
Record:where{Q{buyer__detail__info__weight__gt=20}/Q{seller__detail__info__height__gt=20}}
Record:where{Q{seller__detail__info__weight__gt=20}/Q{buyer__detail__info__height__gt=20}, buyer__detail__info__height__lt=120}:join{'buyer'}
Record:where{Q{seller__detail__info__weight__gt=20}/Q{buyer__detail__info__height__gt=20}, buyer__detail__info__height__lt=120}:join{'buyer', 'seller', 'product'}
```
# Synopsis
Code below shows how easy it is to write a user register logic code.
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
                local user = User:instance(cd) 
                user.age = 22 -- set some value before saving to database
                user.score = 150
                local res, errors = user:save(true) -- `true` means insert a row to database, 
                if not res then
                    return ngx.print('Fail to create user, '..table.concat(errors, '<br/>'))
                else
                    return ngx.print(string.format(
                        'Congratulations! You have created a user successfully! <br/>'
                        ..'id:%s, Name:%s, Password:%s, Age:%s, Score:%s, Create time:%s.'
                        ..'<h1>now please try <a href="/login">login</a><h1>', 
                        user.id, user.username, user.password, user.age, user.score, user.create_time))
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
1. column alias

# Update log
2016-10-07 Foreign key is supported
