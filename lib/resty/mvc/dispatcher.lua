local Request = require"resty.mvc.request"
local Response = require"resty.mvc.response"
local settings = require"resty.mvc.settings"

local Dispatcher = {}
function Dispatcher.new(cls, attrs)
    attrs = attrs or {}
    cls.__index = cls
    return setmetatable(attrs, cls)
end
function Dispatcher.instance(cls, attrs)
    local self = cls:new(attrs)
    assert(self.router and self.middlewares, 'router and middlewares must be set')
    self.request_processors = {}
    self.response_processors = {}
    self.view_processors = {}
    for i, ware in ipairs(self.middlewares) do
        if type(ware) == 'string' then
            ware = require(ware)
        end
        if ware.process_request then
            table.insert(self.request_processors, ware.process_request)
        end
        if ware.process_view then
            table.insert(self.view_processors, ware.process_view)
        end
        if ware.process_response then
            table.insert(self.response_processors, 1, ware.process_response)
        end
    end
    return self
end
function Dispatcher.match(self, uri)
    local view_func, kwargs = self.router:match(uri)
    if not view_func then
        return Response.Error"404":exec()
    end
    local request = Request:new{kwargs=kwargs}
    local response, err
    for i, processor in ipairs(self.request_processors) do
        response, err = processor(request)
        if err or response then
            break
        end
    end
    -- if not response and not err then
    --     for i, processor in ipairs(self.view_processors) do
    --         response, err = processor(request, view_func, kwargs)
    --         if err or response then
    --             break
    --         end
    --     end
    -- end
    if not response and not err then
        response, err = view_func(request)
    end
    if not err and response and response.render then
        response.body = response:render()
    end
    if not err and response then
        for i, processor in ipairs(self.response_processors) do
            response, err = processor(request, response)
            if err or not response then
                break
            end
        end
    end
    if err then
        return ngx.print(err)
    elseif not response then
        return ngx.print("No response object returned.")
    else
        return response:exec()
    end
end



return Dispatcher
    