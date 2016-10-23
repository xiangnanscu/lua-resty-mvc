local get_post = require"resty.reqargs"
local os_remove = os.remove

local function process_request(request)
    request.GET, request.POST, request.FILES = get_post{}
    --loger('request.POST', request.POST)
end
 -- {\\table: 0x001bbb50
 --               "file": "wyj.JPG",  -- or ''
 --               "name": "avatar",
 --               "size": 40509,
 --               "temp": "\s8rk.n",
 --               "type": "image/jpeg",
 --             },
local function process_response(request, response)
    for k, v in pairs(request.FILES) do
        os_remove(v.temp)
    end
    return response
end
return { process_request = process_request, process_response = process_response}