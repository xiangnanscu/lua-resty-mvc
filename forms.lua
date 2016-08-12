local Form = require"resty.model.form"
local BootsForm = require"resty.model.bootstrap_form"
local Field = require"resty.model.field"
local BootsField = require"resty.model.bootstrap_field"
local validator = require"resty.model.validator"
local User = require"models".User

local M = {}
-- UserForm inherits Form directly, so both `Form:class{...}` and `Form{...}` can be used.
M.UserForm = Form{
    fields = {
        username = Field.CharField{maxlength=20, validators={validator.minlen(7)},},    
        password = Field.PasswordField{maxlength=28, validators={validator.minlen(8)},},    
    }, 
    field_order = {'username', 'password'}, 
    clean_username = function(self,value)
        local user = User:get{username=value}
        if user then
            return nil, {'this username already exists.'}
        end
        return value
    end, 
    
}
-- LoginForm inherits BootsForm which inherits Form via `new` method, which means 
-- getmetatable(BootsForm).__call is InstanceCaller rather than ClassCaller. So the 
-- fields can't be resolved with `BootsForm{...}`. We should use `class` method instead.
M.LoginForm = BootsForm:class{
    fields = {
        username = BootsField.CharField{maxlength=20, validators={validator.minlen(6)}, required=false},    
        password = BootsField.PasswordField{maxlength=28, validators={validator.minlen(6)},},    
    }, 
    field_order = {'username', 'password'}, 
    clean_username = function(self, value)
        local user = User:get{username=value}
        if not user then
            return nil, {'username doesnot exists.'}
        end
        self.user = user --for reuses
        return value
    end, 
    clean_password = function(self, value)
        if self.user then
            if self.user.password~=value then
                return nil, {'wrong password.'}
            end
        end
        return value
    end, 
}

return M