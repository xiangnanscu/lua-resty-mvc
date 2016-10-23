local Router = require"resty.mvc.router"
local apps = require"resty.mvc.apps"
local admin = require"resty.mvc.admin"
local settings = require"resty.mvc.settings"

settings.normalize(settings)

local router = Router:instance()
-- '^/product/update/(?<id>\\d+?)$'
-- {
--   "id": "1",
--   0   : "/product/update/1",
--   1   : "1",
-- }
-- for i, v in ipairs(require"main.urls") do
--     router:add(v)
-- end
for i, v in ipairs(apps.get_urls()) do
    router:add(v)
end
for i, v in ipairs(admin.get_urls()) do
    router:add(v)
end

return {
    router = router,
}