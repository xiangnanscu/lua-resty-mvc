local Field = require"resty.model.field" 

local M = {}
M.CharField = Field.CharField:new{attrs={class='form-control'}}
M.PasswordField = Field.CharField:new{type='password', attrs={class='form-control'}}
M.TextField = Field.TextField:new{attrs={cols=40, rows=6, class='form-control'}}
M.OptionField = Field.OptionField:new{attrs={class='form-control'}}
M.RadioField = Field.RadioField:new{attrs={class='radio'}}
M.FileField = Field.FileField:new{attrs={class='form-control'}}

return M