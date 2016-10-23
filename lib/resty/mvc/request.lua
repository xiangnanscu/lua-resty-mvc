local Request = setmetatable({}, {__index=ngx.req})
Request.__index = Request
function Request.new(cls, self)
    self = self or {}
    return setmetatable(self, cls)
end
function Request.is_ajax(self)
    return ngx.var.http_x_requested_with == 'XMLHttpRequest'
end

return Request