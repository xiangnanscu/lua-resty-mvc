local match = ngx.re.match

local M = {}
local function utf8len(s)
    local _, cnt = s:gsub('[^\128-\193]',"")
    return cnt
end
function M.maxlen(max, message)
    message = message or 'length cannot be bigger than '..max
    return function ( value )
        if utf8len(value) > max then
            return message
        end
    end
end
function M.minlen(min, message)
    message = message or 'length cannot be smaller than '..min
    return function ( value )
        if utf8len(value) < min then
            return message
        end
    end
end
function M.max(max, message)
    message = message or 'no bigger than '..max
    return function ( value )
        if value > max then
            return message
        end
    end
end
function M.min(min, message)
    message = message or 'no smaller than '..min
    return function ( value )
        if value < min then
            return message
        end
    end
end
function M.regex(reg, message)
    message = message or 'invalid format'
    return function ( value )
        if not match(value, reg) then
            return message
        end
    end
end

return M