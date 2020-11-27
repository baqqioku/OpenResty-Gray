---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by guoguo.
--- DateTime: 2020/11/21 15:47
---

local modulename = "abtestingAdminGrayServer"


local _M = { _VERSION = "0.0.1" }
local mt = { __index = _M }

local grayServerModule = require('abtesting.adapter.grayserver')
local systemConf    = require('abtesting.utils.init')
local handler       = require('abtesting.error.handler').handler
local utils         = require('abtesting.utils.utils')
local log			= require('abtesting.utils.log')
local ERRORINFO     = require('abtesting.error.errcode').info

local cache         = require('abtesting.utils.cache')


local cjson         = require('cjson.safe')
local doresp        = utils.doresp
local dolog         = utils.dolog
local doerror       = utils.doerror

local prefixConf    = systemConf.prefixConf
local grayserverLib = prefixConf.graySwitchPrefix



local getGrayServer = function()

    local request_body  = ngx.var.request_body
    local postData      = cjson.decode(request_body)

    if not request_body then
        -- ERRORCODE.PARAMETER_NONE
        local errinfo   = ERRORINFO.PARAMETER_NONE
        local desc      = 'request_body or post data'
        local response  = doresp(errinfo, desc)
        log:errlog(dolog(errinfo, desc))
        ngx.say(response)
        return nil
    end

    if not postData then
        -- ERRORCODE.PARAMETER_ERROR
        local errinfo   = ERRORINFO.PARAMETER_ERROR
        local desc      = 'postData is not a json string'
        local response  = doresp(errinfo, desc)
        log:errlog(dolog(errinfo, desc))
        ngx.say(response)
        return nil
    end

    return postData

end

_M.set = function(option)
    local db = option.db

    local garyServer = getGrayServer()
    if not garyServer then
        return false
    end
    local grayServerMod = grayServerModule:new(db.redis, grayserverLib)
    local pfunc = function()
        return grayServerMod:check(garyServer)
    end

    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end

    local chkout    = info
    local valid     = chkout[1]
    local err       = chkout[2]
    local desc      = chkout[3]

    if not valid then
        log:errlog(dolog(err, desc))
        local response = doresp(err, desc)
        ngx.say(response)
        return false
    end

    local pfunc = function()
        return grayServerMod:set(garyServer)
    end

    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    else
        local grayServerCache  = cache:new(ngx.var.kv_gray)

        for _, v in pairs(garyServer) do
            grayServerCache:setGrayServerSwitch(v['name'],v['switch'])
        end

    end

    local data
    if info then
        data = info
    end

    local response = doresp(ERRORINFO.SUCCESS, _, data)
    ngx.say(response)
    return true
end

local getGrayServerName = function()
    local serverName = ngx.var.arg_server_name

    if not serverName then
        local info = ERRORINFO.PARAMETER_NEEDED
        local desc = "server_name invalid"
        local response = doresp(info, desc)
        log:errlog(dolog(info, desc))
        ngx.say(response)
        return nil
    end
    return serverName
end

_M.del = function(option)
    local db = option.db

    local serverName = getGrayServerName()
    if not serverName then
        return false
    end

    local pfunc = function()
        local policyMod = grayServerModule:new(db.redis, grayserverLib)
        return policyMod:del(serverName)
    end

    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end
    local response = doresp(ERRORINFO.SUCCESS)
    ngx.say(response)
    return true
end

_M.get = function(option)
    local db = option.db
    local grayServerName = option.grayServerName
    ngx.log(ngx.DEBUG,grayServerName)
    local serverName
    if grayServerName then
        serverName = grayServerName
    else
        serverName =  getGrayServerName()
    end

    if not serverName then
        return false
    end

    local pfunc = function()
        local grayMod = grayServerModule:new(db.redis, grayserverLib)
        return grayMod:get(grayserverLib,serverName)
    end

    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    else
        local response = doresp(ERRORINFO.SUCCESS, nil, info)
        log:errlog(dolog(ERRORINFO.SUCCESS, nil))
        ngx.say(response)
        return true
    end

end

_M.loadInit = function(option)
    local db = option.db
    local grayserverCache = option.grayserverCache

    local grayfunc = function()
        local gray = grayServerModule:new(db.redis, grayserverLib)
        ngx.log(ngx.DEBUG,'loadAll')
        return gray:loadAll()
    end

    local status, grayServer = xpcall(grayfunc, handler)
    if  status then
        local ok  = grayserverCache:setGrayServer(grayServer)
        if ok then
            return grayServer
        end
    end
end



return _M




