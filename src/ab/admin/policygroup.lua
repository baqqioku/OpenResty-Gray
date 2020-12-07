---
-- @classmod abtesting.adapter.policy
-- @release 0.0.1
local modulename = "abtestingAdminPolicyGroup"

local _M = { _VERSION = "0.0.1" }
local mt = { __index = _M }

local ERRORINFO	= require('abtesting.error.errcode').info


local systemConf    = require('abtesting.utils.init')
local handler       = require('abtesting.error.handler').handler
local utils         = require('abtesting.utils.utils')
local log			= require('abtesting.utils.log')
local ERRORINFO     = require('abtesting.error.errcode').info
local utils         = require('abtesting.utils.utils')


local cjson         = require('cjson.safe')
local doresp        = utils.doresp
local dolog         = utils.dolog
local doerror       = utils.doerror


local divtypes      = systemConf.divtypes
local prefixConf    = systemConf.prefixConf
local policyLib     = prefixConf.policyLibPrefix


local policyGroupModule  = require('abtesting.adapter.policygroup')
local policyGroupLib     = prefixConf.policyGroupPrefix

local getPolicyGroupId = function()
    local policyGroupId      = tonumber(ngx.var.arg_policygroupid)
    if not policyGroupId or policyGroupId < 0 then
        local info = ERRORINFO.PARAMETER_TYPE_ERROR 
        local desc = "policyGroupId invalid"
        local response = doresp(info, desc)
        log:errlog(dolog(info, desc))
        ngx.say(response)
        return nil 
    end
    return policyGroupId
end

--- 根据请求获得策略组数据
--- {
---    "1": {
---        "divtype": "uidappoint",
---        "divdata": [
---            {"uidset": [1234,5124,653],"upstream": "beta1"},
---            {"uidset": [3214,652,145],"upstream": "beta2"}]},
---    "2": {
---        "divtype": "iprange",
---        "divdata": [{"range": {"start": 1111,"end": 2222},"upstream": "beta1"},
---            {"range": {"start": 3333,"end": 4444},"upstream": "beta2"},
---            {"range": {"start": 7777,"end": 8888},"upstream": "beta3"}]}
---}
--- @return 策略组数据

local getPolicyGroup = function()

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

    local policy_cnt = 0
    local policyGroup = {}
    for k, v in pairs(postData) do
        policy_cnt = policy_cnt + 1

        local idx = tonumber(k)
        if not idx or type(v) ~= 'table' then
            local errinfo   = ERRORINFO.PARAMETER_ERROR 
            local desc      = 'policyGroup error'
            local response  = doresp(errinfo, desc)
            log:errlog(dolog(errinfo, desc))
            ngx.say(response)
            return nil
        end

        local policy = v
        local divtype = policy.divtype
        local divdata = policy.divdata

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
            local errinfo   = ERRORINFO.PARAMETER_TYPE_ERROR 
            local desc      = "unsupported divtype"
            local response  = doresp(errinfo, desc)
            log:errlog(dolog(errinfo, desc))
            ngx.say(response)
            return nil
        end

        if policyGroup[idx] then
            --不能混淆，优先级不能重复
            local errinfo   = ERRORINFO.PARAMETER_TYPE_ERROR 
            local desc      = "policy in policy group should not overlap"
            local response  = doresp(errinfo, desc)
            log:errlog(dolog(errinfo, desc))
            ngx.say(response)
            return nil
        end

        policyGroup[idx] = policy
    end

    if policy_cnt ~= #policyGroup then
        local errinfo   = ERRORINFO.PARAMETER_TYPE_ERROR 
        local desc      = "index of policy in policy_group should be one by one"
        local response  = doresp(errinfo, desc)
        log:errlog(dolog(errinfo, desc))
        ngx.say(response)
        return nil
    end

    return policyGroup
end

_M.checkPolicy = function(option)
    local db = option.db

    local policyGroup = getPolicyGroup()
    if not policyGroup then
        return false
    end

    local steps = #policyGroup
    if steps < 1 then 
        local errinfo   = ERRORINFO.PARAMETER_NONE
        local desc      = "blank policy group"
        local response  = doresp(errinfo, desc)
        log:errlog(dolog(errinfo, desc))
        ngx.say(response)
        return false
    end

    local pfunc = function()
        local policyGroupMod = policyGroupModule:new(db.redis,
                                        policyGroupLib, policyLib)
        return policyGroupMod:check(policyGroup)
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
        local response = doresp(err, desc)
        ngx.say(response)
        log:errlog(dolog(err, desc))
        return false
    end

    return true
end

_M.check = function(option)
    local status = _M.checkPolicy(option)
    if not status then return end
    local response = doresp(ERRORINFO.SUCCESS)
    ngx.say(response)
    return true
end

_M.set = function(option)

    local status = _M.checkPolicy(option)
    if not status then return end

    local db = option.db

    local policyGroup = getPolicyGroup()
    if not policyGroup then
        return false
    end

    local pfunc = function()
        local policyGroupMod = policyGroupModule:new(db.redis,
                                        policyGroupLib, policyLib)
        return policyGroupMod:set(policyGroup)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end

    local data = info
    local response = doresp(ERRORINFO.SUCCESS, _, data)
    ngx.say(response)
    return true
end

local getAdminGroup = function()
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

    local policy_cnt = 0
    local policyGroup = {}
    ngx.log(ngx.DEBUG,cjson.encode(postData))
    local policyids = postData['policyids']

    for k, v in pairs(policyids) do
        policy_cnt = policy_cnt + 1
        local idx = tonumber(k)
        local policy = v
        policyGroup[idx] =policy
    end

    if policy_cnt ~= #policyGroup then
        local errinfo   = ERRORINFO.PARAMETER_TYPE_ERROR
        local desc      = "index of policy in policy_group should be one by one"
        local response  = doresp(errinfo, desc)
        log:errlog(dolog(errinfo, desc))
        ngx.say(response)
        return nil
    end
    return policyGroup
end


_M.adminSet = function(option)
    local db = option.db

    local policyGroup = getAdminGroup()
    if not policyGroup then
        return false
    end

    local pfunc = function()
        local policyGroupMod = policyGroupModule:new(db.redis, policyGroupLib, policyLib)
        return policyGroupMod:adminSet(policyGroup)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end

    local data = info
    local response = doresp(ERRORINFO.SUCCESS, _, data)
    ngx.say(response)
    return true

end

_M.get = function(option)
    local db = option.db

    local policyGroupId = getPolicyGroupId()
    if not policyGroupId then
        return false
    end

    local pfunc = function()
        local policyGroupMod = policyGroupModule:new(db.redis,
                                        policyGroupLib, policyLib)
        return policyGroupMod:get(policyGroupId)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end
    local data = info
    local response = doresp(ERRORINFO.SUCCESS, _, data)
    ngx.say(response)
    return true
end

_M.list = function(option)
    local db = option.db

    local pfunc = function()
        local policyGroupMod = policyGroupModule:new(db.redis, policyGroupLib, policyLib)
        return policyGroupMod:list()
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end

    local response = doresp(ERRORINFO.SUCCESS, nil, info)
    ngx.say(response)
    return true
end

return _M
