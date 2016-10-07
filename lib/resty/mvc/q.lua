local string_format = string.format

local function __unm(t) --neg
    if t.negated == nil then
        t.negated = true
    else
        t.negated = nil
    end
    return t
end
local function __mul(t, o) --and
    local n = t.new()
    n.left = t
    n.right = o
    n.op = 'AND'
    return n
end
local function __div(t, o) --or
    local n = t.new()
    n.left = t
    n.right = o
    n.op = 'OR'
    return n
end

local Q = {__unm=__unm, __mul=__mul, __div=__div}
Q.__index = Q
setmetatable(Q, {__call = function(t, a) return t.instance(a) end})

function Q.serialize(self, manager)
    local neg = ''
    if self.negated then
        neg = 'NOT '
    end
    if self.op == nil then
        return string_format('%s(%s)', neg, manager:_parse_params(self.args, self.kwargs))
    else -- AND or OR
        return string_format('%s(%s %s %s)', neg, self.left:serialize(manager), self.op, self.right:serialize(manager))
    end
end
function Q.new()
    return setmetatable({}, Q)
end
function Q.instance(kwargs)
    local self = Q.new()
    local args = {}
    for k, v in pairs(kwargs) do
        if type(k) == 'number' then
            args[#args+1] = v
            kwargs[k] = nil
        end 
    end
    self.args = args
    self.kwargs = kwargs
    return self
end

return Q