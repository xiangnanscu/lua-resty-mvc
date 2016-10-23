local function init()
    -- create table in the database
    local query = require"resty.mvc.query".single
    local res, err = query("SET FOREIGN_KEY_CHECKS=0;")
    if not res then
        return ngx.print('Fail to turn off foreign key checks, '..err)
    end
    res, err = query("drop table if exists account_user")
    if not res then
        return ngx.print('Fail to drop table `account_user`, '..err)
    end
    res, err = query("SET FOREIGN_KEY_CHECKS=1;")
    if not res then
        return ngx.print('Fail to turn on foreign key checks, '..err)
    end
    res, err = query(
[[CREATE TABLE `account_user` (
`id` int(10) unsigned NOT NULL AUTO_INCREMENT,
`update_time` datetime NOT NULL,
`create_time` datetime NOT NULL,
`username` varchar(20) NOT NULL,
`password` varchar(28) NOT NULL,
`passed` tinyint(4) NOT NULL,
`class` varchar(5) NOT NULL,
`age` int(11) NOT NULL,
`score` float NOT NULL,
PRIMARY KEY (`id`),
UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;]])
    if not res then
        return ngx.print('Fail to create a table `account_user`, '..err)
    end
    return ngx.print(
        'Congratulations! You have created table `account_user`'
        ..'<h1>now please try <a href="/register">register</a></h1>.')
end

local function register()
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
end

local function login()
    local LoginForm = require"forms".LoginForm
    local User = require"models".User
    local req = ngx.req
    local form;

    if req.get_method()=='POST' then
        req.read_body()
        form = LoginForm:instance{data=req.get_post_args()}
        if form:is_valid() then
            return ngx.print(
                'Congratulations! You have passed the login test, '
                ..' your first experience to `lua-resty-mvc` is over.')
        end
    else
        form = LoginForm:instance{}
    end
    local form_template=[[
<!DOCTYPE html>
<head>
<title>lua-resty-mvc</title> 
</head>
<form method="post">
%s
<button type="submit">login</button>
</form>
</body>
</html>]]
    return ngx.print(string.format(form_template, form:render()))
end


return {
    init = init, 
    register = register, 
    login = login, 

}