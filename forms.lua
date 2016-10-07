local Form = require"resty.mvc.form"
local Field = require"resty.mvc.formfield"
local Widget = require"resty.mvc.widget"
local Validator = require"resty.mvc.validator"
local User = require"models".User


local LoginForm = Form:class{

    fields = {
        username = Field.CharField{
            maxlen=20,  
            minlen=6, 
        },    
        password = Field.PasswordField{
            maxlen=28, 
            minlen=8, 
            widget=Widget.TextInput:instance{placeholder='enter your password', title='enter your password', foo='bar'},
        },     
    }, 

    field_order = {'username', 'password'}, 

    clean_username = function(self, value)
        local user = User:get{username=value}
        if not user then
            return nil, {'username does not exists.'}
        end
        self.user = user --for reuses
        return value
    end, 

    clean_password = function(self, value)
        if self.user then
            if self.user.password ~= value then
                return nil, {'wrong password.'}
            end
        end
        return value
    end, 
}

local UserForm = Form:class{

    fields = {
        username = Field.CharField{
            maxlen=20,  
            minlen=6, 
            initial='abcdef', 
            widget=Widget.TextInput:instance{placeholder='your name here, at least 6.'},
        },    
        password = Field.PasswordField{
            maxlen=28, 
            minlen=8, 
        },    
    }, 

    field_order = {'username', 'password'}, 

    clean_username = function(self, value)
        local user = User:get{username=value}
        if user then
            return nil, {'username already exists.'}
        end
        return value
    end, 
}

return {
    UserForm = UserForm, 
    LoginForm = LoginForm, 
}