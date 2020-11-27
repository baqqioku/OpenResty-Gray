

local grayServer = require('admin.grayserver')
local redisModule   = require('abtesting.utils.redis')
local systemConf    = require('abtesting.utils.init')
local cache         = require('abtesting.utils.cache')


local redisConf	    = systemConf.redisConf

--local grayServerCache = ngx.shared.kv_gray_server

local red = redisModule:new(redisConf)
local ok, err = red:connectdb()
if not ok then
    local info = ERRORINFO.REDIS_CONNECT_ERROR
    local response = doresp(info, err)
    dolog(info, desc)
    ngx.say(response)
    return
end


local loadGrayServer = function()
    local grayServerCache  = cache:new('kv_api_root_grayServer')
    grayServer.loadInit({['db']=red,['grayserverCache']=grayServerCache})
    ngx.log(ngx.DEBUG,grayServerCache:getGrayServer("driver"))
end

loadGrayServer()





