local function process_request(request)
    request.messages = request.session.messages
end

local function process_response(request, response)
    if request.messages then
        request.session.messages = nil
    end
end
return { process_request = process_request, process_response = process_response}