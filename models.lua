local Query = require"resty.mvc.query".single
local Model = require"resty.mvc.model"
local Field = require"resty.mvc.field"

local M = {}

M.User = Model:class{table_name='users', 
    fields = {
        id = Field.IntegerField{min=1}, 
        username = Field.CharField{maxlength=50},
        avatar = Field.CharField{maxlength=100},  
        openid = Field.CharField{maxlength=50}, 
        password = Field.PasswordField{maxlength=50}, 
    }, 
}

return M