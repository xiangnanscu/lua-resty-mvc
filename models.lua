local Model = require"resty.mvc.model"
local Field = require"resty.mvc.modelfield"

local User = Model:new{
    fields = {
        username = Field.CharField{maxlen=20, minlen=6, unique=true},
        password = Field.CharField{maxlen=28, minlen=8},
        age = Field.IntegerField{min=6, max=100, default=1},
        score = Field.FloatField{min=0, max=150, default=0},
        class = Field.CharField{maxlen=5, default='1', choices={{'1', 'class one'}, {'2', 'class two'}}},
        passed = Field.BooleanField{default=false},
        create_time = Field.DateTimeField{auto_now_add=true},
        update_time = Field.DateTimeField{auto_now=true}
    }, 
}

return {
    User = User:normalize('account','User'),
}