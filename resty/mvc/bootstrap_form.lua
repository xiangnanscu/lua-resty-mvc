local Form = require"resty.mvc.form"

local M = Form:new{
    row_template = [[<div class="form-group"> %s %s %s %s </div>]],
    error_template = [[<div class="alert alert-danger" role="alert"><ul class="error">%s</ul></div>]],
    help_template = [[<p class="help-block">%s</p>]],
}

return M