local Row = require"resty.mvc.row"
local User = require"apps.account.models".User

local row_class = Row:new{__model=User}

local function process_request(request)
	local user = request.session.user
	if user then
    	request.user = row_class:instance(user)
   	end
end

return { process_request = process_request}