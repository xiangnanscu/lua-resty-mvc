local Bootstrap = require"resty.mvc.bootstrap"
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
        if self.debug then
            ngx.header['Content-Type'] = "text/plain; charset=utf-8"
            return ngx.print("can't find this uri, current router is:\n"..repr(router))
        else
            return ngx.print("404")
        end
    end
    local request = Request:new{kwargs=kwargs}
    local response, err
    for i, processor in ipairs(self.request_processors) do
        response = processor(request)
        if response then
            break
        end
    end
    if not response then
        for i, processor in ipairs(self.view_processors) do
            response = processor(request, view_func, kwargs)
            if response then
                break
            end
        end
    end
    if not response then
        response = view_func(request)
        if not response then
            return ngx.print("No response object returned.")
        end
    end
    if response.render then
        response.body = response:render()
    end
    for i, processor in ipairs(self.response_processors) do
        response = processor(request, response)
        if not response then
            return ngx.print("No response object returned.")
        end
    end
    return response:exec()
end

local dispatcher = Dispatcher:instance{
    router = Bootstrap.router,
    middlewares = settings.MIDDLEWARES,
    debug = settings.debug,
}

return function() 
    return dispatcher:match(ngx.var.uri) end
    