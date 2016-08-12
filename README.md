# lua-resty-mvc
**You don't need that complicated MVC framework!**
With just a plain folder with several simple files, you can enjoy basic but most frequently used MVC features.
# Synopsis
```
location = /register {
    content_by_lua_block{
        -- create table in the database
        local Query = require"resty.mvc.query".single
        local res, err = Query("drop table if exists users")
        assert(res, err)
        res, err = Query([[create table users(
            id        serial primary key,
            username  varchar(50), 
            avatar    varchar(15), 
            openid    integer,  
            password  varchar(50));]])
        assert(res, err)

        -- MVC stuff starts
        local UserForm = require"forms".UserForm
        local User = require"models".User
        local req = ngx.req
        local form;

        if req.get_method()=='POST' then
            req.read_body()
            form = UserForm{data=req.get_post_args()}
            if form:is_valid() then
                local cd=form.cleaned_data
                local user, err=User(cd):save()
                if not user then
                    return ngx.print(err)
                end
                user = User:get{id=1}
                return ngx.print(string.format(
                    'Congratulations! You have created a user successfully!'
                    ..'Name:%s, Password:%s', user.username, user.password))
            end
        else
            form = UserForm{}
        end
        local form_template=[[
            <!DOCTYPE html>
            <head>
              <link href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css" rel="stylesheet">
              <title>MVC</title> 
            </head>
            <body>
              <div class="container-fluid">
              <div class="row">
                <div class="col-md-4"> </div>
                <div class="col-md-4">
                    <form method="post" action="">
                      %s
                      <button type="submit">register</button>
                    </form>
                </div>
                <div class="col-md-4"> </div>
              </div>
              <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.12.4/jquery.min.js"></script>
              <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js"></script>
            </body>
            </html>]]
        return ngx.print(string.format(form_template, form:render()))
    }
}
```
# Todo
1. Foreign keys support
2. Auto create database table from Model if neccessary.
