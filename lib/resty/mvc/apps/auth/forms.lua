local Form = require"resty.mvc.form"
local Field = require"resty.mvc.formfield"
local Validator = require"resty.mvc.validator"
local auth = require"resty.mvc.apps.auth"

local User = auth.get_user_model()

local LoginForm = Form:class{
    
    fields = {
        username = Field.CharField{maxlen=20, minlen=3},    
        password = Field.PasswordField{maxlen=128, minlen=3},    
    }, 

    -- ensure `username` is rendered and checked before `password`
    field_order = {'username', 'password'}, 
    
    clean_username = function(self, value)
        local user = User:get{username=value}
        if not user then
            return nil, {"username doesn't exist."}
        end
        if user.permission ~= 's' then
            return nil, {"you've no permission to login"}
        end
        self.user = user -- used in `clean_password` later
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

return {
    LoginForm = LoginForm,
}