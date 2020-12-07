---
-- @classmod abtesting.adapter.policy
-- @release 0.0.1
local modulename = "abtestingAdminPolicy"

local _M = { _VERSION = "0.0.1" }
local mt = { __index = _M }

local ERRORINFO	= require('abtesting.error.errcode').info

local runtimeModule = require('abtesting.adapter.runtime')
local policyModule  = require('abtesting.adapter.policy')
local redisModule   = require('abtesting.utils.redis')
local systemConf    = require('abtesting.utils.init')
local handler       = require('abtesting.error.handler').handler
local utils         = require('abtesting.utils.utils')
local log			= require('abtesting.utils.log')
local ERRORINFO     = require('abtesting.error.errcode').info

local cjson         = require('cjson.safe')
local doresp        = utils.doresp
local dolog         = utils.dolog
local doerror       = utils.doerror

local redisConf     = systemConf.redisConf
local divtypes      = systemConf.divtypes
local prefixConf    = systemConf.prefixConf
local policyLib     = prefixConf.policyLibPrefix
local runtimeLib    = prefixConf.runtimeInfoPrefix
local domain_name   = prefixConf.domainname

local getPolicyId = function()
    local policyID = tonumber(ngx.var.arg_policyid)

    if not policyID or policyID < 0 then
        local info = ERRORINFO.PARAMETER_TYPE_ERROR 
        local desc = "policyID invalid"
        local response = doresp(info, desc)
        log:errlog(dolog(info, desc))
        ngx.say(response)
        return nil 
    end
    return policyID
end

local getPolicy = function()

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

    local divtype = postData.divtype
    local divdata = postData.divdata

    if not divtype or not divdata then
        -- ERRORCODE.PARAMETER_NONE
        local errinfo   = ERRORINFO.PARAMETER_NONE 
        local desc      = "policy divtype or policy divdata"
        local response  = doresp(errinfo, desc)
        log:errlog(dolog(errinfo, desc))
        ngx.say(response)
        return nil
    end

    if not divtypes[divtype] then
        -- ERRORCODE.PARAMETER_TYPE_ERROR
        --如果是小流量给他初始化一个值
        if divtype == 'flowratio' then
            local prefix = ngx.var.hostkey
            strategyCache:set(prefix .. "_count",0)
            ngx.log(ngx.INFO, "timer_at run worker:",ngx.worker.id())
        end
        local errinfo   = ERRORINFO.PARAMETER_TYPE_ERROR 
        local desc      = "unsupported divtype"
        local response  = doresp(errinfo, desc)
        log:errlog(dolog(errinfo, desc))
        ngx.say(response)
        return nil
    end

    return postData

end

_M.check = function(option)
    local db = option.db

    local policy = getPolicy()
    if not policy then
        return false
    end

    local pfunc = function() 
        local policyMod = policyModule:new(db.redis, policyLib)
        return policyMod:check(policy)
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

    local response
    if not valid then
        log:errlog(dolog(err, desc))
        response = doresp(err, desc)
    else
        response = doresp(ERRORINFO.SUCCESS)
    end
    ngx.say(response)
    return true

end

_M.set = function(option)
    local db = option.db

    local policy = getPolicy()
    if not policy then
        return false
    end

    local pfunc = function() 
        policyMod = policyModule:new(db.redis, policyLib)
        return policyMod:check(policy)
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
        return policyMod:set(policy)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end
    local data
    if info then
        data = ' the id of new policy is '..info
    end

    local response = doresp(ERRORINFO.SUCCESS, data)
    ngx.say(response)
    return true

end

_M.update = function(option)
    local db = option.db
    local policyId = getPolicyId()
    if not policyId then
        return false
    end

    local policy = getPolicy()
    if not policy then
        return false
    end

    local pfunc = function()
        policyMod = policyModule:new(db.redis, policyLib)
        return policyMod:check(policy)
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

    local delPfunc = function()
        return policyMod:del(policyId)
    end
    local status, info = xpcall(delPfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end

    local pfunc = function()
        return policyMod:update(policy,policyId)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end

    local data
    if info then
        data = ' the id '..policyId..' of  policy is update '..info
    end

    local response = doresp(ERRORINFO.SUCCESS, data)
    ngx.say(response)
    return true

end

_M.del = function(option)
    local db = option.db

    local policyId = getPolicyId()
    if not policyId then
        return false
    end

    local pfunc = function()
        local policyMod = policyModule:new(db.redis, policyLib) 
        return policyMod:del(policyId)
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

    local policyId = getPolicyId()
    if not policyId then
        return false
    end

    local pfunc = function()
        local policyIO = policyModule:new(db.redis, policyLib) 
        return policyIO:get(policyId)
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

_M.list = function(option)
    local db = option.db
    local pfunc = function()
        local policyIO = policyModule:new(db.redis, policyLib)
        return policyIO:list()
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


_M.pageList = function(option)
    local db = option.db
    local page = ngx.var.arg_page
    local size = ngx.var.arg_size
    local pfunc = function()
        local policyIO = policyModule:new(db.redis, policyLib)
        return policyIO:list(page,size)
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

return _M
