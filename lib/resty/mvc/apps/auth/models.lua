local Model = require"resty.mvc.model"
local Field = require"resty.mvc.modelfield"
local Validator = require"resty.mvc.validator"

local User = Model:new{
    meta   = {
        
    },
    fields = {
        username = Field.CharField{minlen=3, maxlen=20, unique=true},
        password = Field.CharField{minlen=3, maxlen=128},
        permission = Field.CharField{minlen=1, maxlen=20},
    }
}

function User.render(self)
    return self.username
end

return {
    User = User,
}