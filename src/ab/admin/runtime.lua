---
-- @classmod abtesting.adapter.policy
-- @release 0.0.1
local modulename = "abtestingAdminRuntime"

local _M = { _VERSION = "0.0.1" }
local mt = { __index = _M }


local runtimeModule = require('abtesting.adapter.runtime')
local policyModule  = require('abtesting.adapter.policy')
local systemConf    = require('abtesting.utils.init')
local handler       = require('abtesting.error.handler').handler
local utils         = require('abtesting.utils.utils')
local log			= require('abtesting.utils.log')
local ERRORINFO     = require('abtesting.error.errcode').info

local cache         = require('abtesting.utils.cache')


local prefixConf    = systemConf.prefixConf
local runtimeLib    = prefixConf.runtimeInfoPrefix
local policyLib     = prefixConf.policyLibPrefix
local divtypes      = systemConf.divtypes
local fields        = systemConf.fields

local runtimeGroupModule = require('abtesting.adapter.runtimegroup')


local doresp        = utils.doresp
local dolog         = utils.dolog
local doerror       = utils.doerror

local getPolicyId = function()
    local policyID = tonumber(ngx.var.arg_policyid)
    return policyID
end

local getPolicyGroupId = function()
    local policyGroupId = tonumber(ngx.var.arg_policygroupid)
    return policyGroupId
end

local getHostName = function()
    local hostname = ngx.var.arg_hostname
    return hostname
end

local getDivSteps = function()
    local divsteps = tonumber(ngx.var.arg_divsteps)
    return divsteps
end

_M.get = function(option)
    local db = option.db
    local database = db.redis

    local hostname = getHostName()
    if not hostname or string.len(hostname) < 1 or hostname == ngx.null then
        local info = ERRORINFO.PARAMETER_TYPE_ERROR 
        local desc = 'arg hostname invalid: '
        local response = doresp(info, desc)
        log:errlog(dolog(info, desc))
        ngx.say(response)
        return nil 
    end

    local pfunc = function()
        local runtimeGroupMod = runtimeGroupModule:new(database, runtimeLib)
        return runtimeGroupMod:get(hostname)
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



_M.del = function(option)
    local db = option.db
    local database = db.redis

    local hostname = getHostName()
    if not hostname or string.len(hostname) < 1 or hostname == ngx.null then
        local info = ERRORINFO.PARAMETER_TYPE_ERROR
        local desc = 'arg hostname invalid: '
        local response = doresp(info, desc)
        log:errlog(dolog(info, desc))
        ngx.say(response)
        return nil
    end

    local pfunc = function()
        local runtimeGroupMod = runtimeGroupModule:new(database, runtimeLib)
        return runtimeGroupMod:del(hostname)
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




--- 根据请求提供的运行数据，设置新的运行时信息
--- 可以使用策略id，也可以使用策略组id
--- 策略id优先
--- 策略id对应runtime，策略组id对应runtimegroup
_M.set = function(option)
    local policyId = getPolicyId()
    local policyGroupId = getPolicyGroupId()

    if policyId and policyId >= 0 then
        _M.runtimeset(option, policyId)
    elseif policyGroupId and policyGroupId >= 0 then
        _M.groupset(option, policyGroupId)
    else
        local info = ERRORINFO.PARAMETER_TYPE_ERROR
        local desc = "policyId or policyGroupid invalid"
        local response = doresp(info, desc)
        log:errlog(dolog(info, desc))
        ngx.say(response)
        return nil
    end
end

_M.update = function(option)

    local db = option.db
    local database = db.redis
    local policyId = getPolicyId()
    local policyGroupId = getPolicyGroupId()
    local preHostName = ngx.var.arg_prehostname

    if not preHostName or string.len(preHostName) < 1 or preHostName == ngx.null then
        local info = ERRORINFO.PARAMETER_TYPE_ERROR
        local desc = 'arg preHostName invalid: '
        local response = doresp(info, desc)
        log:errlog(dolog(info, desc))
        ngx.say(response)
        return nil
    end

    local statusPfunc = function()
        local statusKey           = runtimeLib .. ':' .. preHostName .. ':' .. fields.status
        local status, err = database:get(statusKey)
        if not status then error{ERRORINFO.REDIS_ERROR, err} end
        return status;
    end

    local ok, info = xpcall(statusPfunc, handler)
    if not ok then
        local response = doerror(info)
        ngx.say(response)
        return false
    elseif info == ngx.null then
        --如果没有给他一个状态
        info = 1
    end
    ngx.log(ngx.DEBUG,'状态:'..info)
    option.status = info


    local pfunc = function()
        local runtimeGroupMod = runtimeGroupModule:new(database, runtimeLib)
        return runtimeGroupMod:updateDel(preHostName)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end

    if policyId and policyId >= 0 then
        _M.runtimeset(option, policyId)
    elseif policyGroupId and policyGroupId >= 0 then
        _M.groupset(option, policyGroupId)
    else
        local info = ERRORINFO.PARAMETER_TYPE_ERROR
        local desc = "policyId or policyGroupid invalid"
        local response = doresp(info, desc)
        log:errlog(dolog(info, desc))
        ngx.say(response)
        return nil
    end
end

--- 根据请求提供的运行数据，编辑新的运行时信息
--- 可以使用策略id，也可以使用策略组id
--- 策略id优先
--- 策略id对应runtime，策略组id对应runtimegroup
_M.admin_get = function(option)
    local db = option.db
    local database = db.redis

    local hostname = getHostName()
    if not hostname or string.len(hostname) < 1 or hostname == ngx.null then
        local info = ERRORINFO.PARAMETER_TYPE_ERROR
        local desc = 'arg hostname invalid: '
        local response = doresp(info, desc)
        log:errlog(dolog(info, desc))
        ngx.say(response)
        return nil
    end

    local pfunc = function()
        local runtimeGroupMod = runtimeGroupModule:new(database, runtimeLib)
        return runtimeGroupMod:get(hostname)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end

    local runtimeInfo = {}
    runtimeInfo.status = info.status
    runtimeInfo.single = info.single
    runtimeInfo.group = info.group
    runtimeInfo.divsteps = info.divsteps
    local response = doresp(ERRORINFO.SUCCESS, nil, runtimeInfo)
    ngx.say(response)
    return true
end



_M.groupset = function(option, policyGroupId)
    local db = option.db
    local database = db.redis

    local hostname = getHostName()
    local divsteps = getDivSteps()
    local preStatus = option.status

    if not hostname or string.len(hostname) < 1 or hostname == ngx.null then
        local info = ERRORINFO.PARAMETER_TYPE_ERROR 
        local desc = 'arg hostname invalid: '
        local response = doresp(info, desc)
        log:errlog(dolog(info, desc))
        ngx.say(response)
        return nil 
    end

    local pfunc = function()
        local runtimeGroupMod = runtimeGroupModule:new(database, runtimeLib)
        runtimeGroupMod:del(hostname)
        return runtimeGroupMod:set(hostname, policyGroupId, divsteps,preStatus)
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

_M.runtimeset = function(option, policyId)
    local db = option.db
    local database = db.redis
    local preStatus = option.status

    local hostname = getHostName()
    local divsteps = 1

    if not hostname or string.len(hostname) < 1 or hostname == ngx.null then
        local info = ERRORINFO.PARAMETER_TYPE_ERROR 
        local desc = 'arg hostname invalid: '
        local response = doresp(info, desc)
        log:errlog(dolog(info, desc))
        ngx.say(response)
        return nil 
    end

    local pfunc = function()
        local runtimeGroupMod = runtimeGroupModule:new(database, runtimeLib)
        return runtimeGroupMod:del(hostname)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end

    local pfunc = function()
        local policyMod = policyModule:new(database, policyLib)
        local policy = policyMod:get(policyId)

        local divtype = policy.divtype
        local divdata = policy.divdata

        if divtype == ngx.null or divdata == ngx.null then
            error{ERRORINFO.POLICY_BLANK_ERROR, 'policy NO '..policyId}
        end

        if not divtypes[divtype] then

        end

        local prefix             = hostname .. ':first'
        local divModulename      = table.concat({'abtesting', 'diversion', divtype}, '.')
        local divDataKey         = table.concat({policyLib, policyId, fields.divdata}, ':')
        local userInfoModulename = table.concat({'abtesting', 'userinfo', divtypes[divtype]}, '.')
        local runtimeMod         = runtimeModule:new(database, runtimeLib) 
        runtimeMod:set(prefix, divModulename, divDataKey, userInfoModulename)

        local divSteps           = runtimeLib .. ':' .. hostname .. ':' .. fields.divsteps
        local statusKey          = runtimeLib .. ':' .. hostname .. ':' .. fields.status
        local hostRelation       = runtimeLib .. ':' .. hostname .. ':' .. fields.single;
        local ok, err = database:set(divSteps, divsteps)

        --是为了兼容更新操作

        if preStatus then
            local ok1,err = database:set(statusKey,preStatus)
        else
            local ok1,err = database:set(statusKey,1)
        end

        local ok2,err = database:set(hostRelation,policyId)
        if   not ok2 then error{ERRORINFO.REDIS_ERROR, err} end

     end

    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end

    local sysConfig =  cache:new(ngx.var.sysConfig)
    sysConfig:setDomain(hostname)
    local response = doresp(ERRORINFO.SUCCESS)
    ngx.say(response)
    return true
end

_M.list = function(option)
    local db = option.db
    local database = db.redis

    local pfunc = function()
        local runtimeGroupMod = runtimeGroupModule:new(database, runtimeLib)
        return runtimeGroupMod:list()
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

_M.pageList = function(option)
    local db = option.db

    local page = ngx.var.arg_page
    local size = ngx.var.arg_size
    local grayfunc = function()
        local runtimeGroupMod = runtimeGroupModule:new(db.redis, runtimeLib)
        return runtimeGroupMod:pageList(page,size)
    end

    local status, info = xpcall(grayfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    else
        local response = doresp(ERRORINFO.SUCCESS, nil, info)
        log:info(dolog(ERRORINFO.SUCCESS, nil))
        ngx.say(response)
        return true
    end
end

_M.changeStatus = function(option)
    local db = option.db
    local database = db.redis
    local hostname = getHostName()
    local status =  ngx.var.arg_status
    if not hostname or string.len(hostname) < 1 or hostname == ngx.null then
        local info = ERRORINFO.PARAMETER_TYPE_ERROR
        local desc = 'arg hostname invalid: '
        local response = doresp(info, desc)
        log:errlog(dolog(info, desc))
        ngx.say(response)
        return nil
    end

    if not status or string.len(status) < 1 or status == ngx.null then
        local info = ERRORINFO.PARAMETER_TYPE_ERROR
        local desc = 'arg status invalid: '
        local response = doresp(info, desc)
        log:errlog(dolog(info, desc))
        ngx.say(response)
        return nil
    end


    local pfunc = function()
        local statusKey           = runtimeLib .. ':' .. hostname .. ':' .. fields.status
        local ok, err = database:set(statusKey, status)
        if not ok then error{ERRORINFO.REDIS_ERROR, err} end
    end

    local ok, info = xpcall(pfunc, handler)
    if not ok then
        local response = doerror(info)
        ngx.say(response)
        return false
    end
    ngx.log(ngx.DEBUG,ngx.var.sysConfig)

    local systemConfCache  = cache:new(ngx.var.sysConfig)
    systemConfCache:setStatus(hostname,status)

    local response = doresp(ERRORINFO.SUCCESS)
    ngx.say(response)
    return true
end



return _M
