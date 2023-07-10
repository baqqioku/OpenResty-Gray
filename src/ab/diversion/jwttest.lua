

local upstream = nil

local read = function()

    local jwtParser = require("abtesting.userinfo.jwtParser")

    local uid = jwtParser:get();
    ngx.log(ngx.DEBUG,"jwt ---------------------")
    for k,v in ipairs(uid) do
        --print(k,v)
        ngx.log(ngx.DEBUG,"jwt "..k..":"..v)
    end

    --ngx.log(ngx.DEBUG,"jwt "..uid)

end

read()

if (upstream)  then
    ngx.var.backend = upstream
end