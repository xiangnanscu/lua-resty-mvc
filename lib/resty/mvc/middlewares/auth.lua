local Row = require"resty.mvc.row"
local auth = require"resty.mvc.apps.auth"

local User = auth.get_user_model()
local row_class = Row:new{__model=User}

local function process_request(request)
	local user = request.session.user
	if user then
    	request.user = row_class:instance(user)
   	end
end

return { process_request = process_request}