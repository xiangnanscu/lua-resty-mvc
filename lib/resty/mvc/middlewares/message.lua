local function delete_after_render(t)
    t.request.session.message = nil
    return t.data
end
-- message is deleted automatically when it's been rendered.
local MessageMeta = {__tostring = delete_after_render}

local function process_request(request)
    local data = request.session.message
    if data then
        request.message = setmetatable({data = data, request = request}, MessageMeta)
    end
end

return { process_request = process_request, process_response = process_response}