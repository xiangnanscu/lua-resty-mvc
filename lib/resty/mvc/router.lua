-- router perform plain or regex match
local match = ngx.re.match

local Router = {}

function Router.new(cls, self)
    self = self or {}
    cls.__index = cls
    return setmetatable(self, cls)
end

function Router.instance(cls)
    local self = cls:new()
    self.plain_matchs = {} 
    self.regex_matchs = {}
    return self
end

function Router.add(self, e)
    -- e should be a array with 2 or 3 elements, e.g.
    -- {'/path', view_callback} or {'/path', view_callback, true}
    if e[3] or e[1]:sub(1,1) == '^' then 
        -- e[3] means this path shoud be regex matched
        self.regex_matchs[#self.regex_matchs+1] = e
    else
        -- this path should be plain matched
        self.plain_matchs[e[1]] = e[2]
    end
    return self
end

function Router.match(self, uri)
    -- first perform plain match (a hash lookup)
    local func = self.plain_matchs[uri]
    if func then
        return func
    end
    -- then perform regex match
    for i, v in ipairs(self.regex_matchs) do
        local regex, func = v[1], v[2]
        local kwargs, err = match(uri, regex, 'jo')
        if kwargs then
            return func, kwargs
        end
    end
end

return Router