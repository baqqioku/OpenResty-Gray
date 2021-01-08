local modulename = "abtestingCache"

local _M = {}
_M._VERSION = '0.0.1'

local ERRORINFO     = require('abtesting.error.errcode').info
local systemConf    = require('abtesting.utils.init')

local prefixConf    = systemConf.prefixConf
local runtimeLib    = prefixConf.runtimeInfoPrefix

local indices       = systemConf.indices
local fields        = systemConf.fields

local divConf       = systemConf.divConf
local shdict_expire = divConf.shdict_expire
local separator = ":"

_M.new = function(self, sharedDict)
    if not sharedDict then
        error{ERRORINFO.ARG_BLANK_ERROR, 'cache name valid from nginx.conf'}
    end

    self.cache = ngx.shared[sharedDict]
    if not self.cache then
        error{ERRORINFO.PARAMETER_ERROR, 'cache name [' .. sharedDict .. '] valid from nginx.conf'}
    end

    return setmetatable(self, { __index = _M } )
end

local isNULL = function(v)
    return not v or v == ngx.null
end

local areNULL = function(v1, v2, v3)
    if isNULL(v1) or isNULL(v2) or isNULL(v3) then
        return true
    end
    return false 
end

_M.getSteps = function(self, hostname)
    local cache = self.cache
    local k_divsteps    = runtimeLib..':'..hostname..':'..fields.divsteps
    local divsteps      = cache:get(k_divsteps)
    return tonumber(divsteps)
end

_M.getStatus = function(self, hostname)
    local cache = self.cache
    local k_status    = runtimeLib..':'..hostname..':'..fields.status
    local status      = cache:get(k_status)
    return tonumber(status)
end

_M.setStatus = function(self, hostname,status)
    local cache = self.cache
    local k_status    = runtimeLib..':'..hostname..':'..fields.status
    local status      = cache:set(k_status,status,shdict_expire)
    return tonumber(status)
end

_M.getRuntime = function(self, hostname, divsteps,status)
    local cache = self.cache
    local runtimegroup = {}
    local prefix = runtimeLib .. ':' .. hostname
    for i = 1, divsteps do
        local idx = indices[i]
        local k_divModname      = prefix .. ':'..idx..':'..fields.divModulename
        local k_divDataKey      = prefix .. ':'..idx..':'..fields.divDataKey
        local k_userInfoModname = prefix .. ':'..idx..':'..fields.userInfoModulename

        local divMod, err1        = cache:get(k_divModname)
        local divPolicy, err2     = cache:get(k_divDataKey)
        local userInfoMod, err3   = cache:get(k_userInfoModname)

        if areNULL(divMod, divPolicy, userInfoMod) then
            return false
        end

        local runtime = {}
        runtime[fields.divModulename  ] = divMod
        runtime[fields.divDataKey     ] = divPolicy
        runtime[fields.userInfoModulename] = userInfoMod
        runtimegroup[idx] = runtime
    end

    runtimegroup.status = tonumber(status)
    return true, runtimegroup

end

_M.setRuntime = function(self, hostname, divsteps,status, runtimegroup)
    local cache = self.cache
    local prefix = runtimeLib .. ':' .. hostname
    local expire = shdict_expire

    for i = 1, divsteps do
        local idx = indices[i]

        local k_divModname      = prefix .. ':'..idx..':'..fields.divModulename
        local k_divDataKey      = prefix .. ':'..idx..':'..fields.divDataKey
        local k_userInfoModname = prefix .. ':'..idx..':'..fields.userInfoModulename

        local runtime = runtimegroup[idx]
        local ok1, err = cache:set(k_divModname, runtime[fields.divModulename], expire)
        local ok2, err = cache:set(k_divDataKey, runtime[fields.divDataKey], expire)
        local ok3, err = cache:set(k_userInfoModname, runtime[fields.userInfoModulename], expire)
        if areNULL(ok1, ok2, ok3) then return false end

    end

    local k_divsteps = prefix ..':'..fields.divsteps
    local k_status   = prefix ..':'..fields.status
    local ok, err = cache:set(k_divsteps, divsteps, shdict_expire)
    local ok1, err = cache:set(k_status,status,shdict_expire)
    if not ok and not ok1 then return false end

    return true
end

_M.getUpstream = function(self,hostname, divsteps, usertable)
    local upstable = {}
    local cache = self.cache
    for i = 1, divsteps do
        local idx   = indices[i]
        local info  = usertable[idx]
        ngx.log(ngx.DEBUG,"获取实际的upstream 键值: ",info)
        --info 获取到了实际的 uid 值
        -- ups will be an actually value or nil
        if info then
            local key = hostname..separator..info
            ngx.log(ngx.DEBUG,"获取拼接后的 upstream 键值: ",key)
            local ups   = cache:get(key)
            upstable[idx] = ups

        end
    end
    return upstable
end

_M.setUpstream = function(self,hostname, info, upstream)
    local cache  = self.cache
    local expire = shdict_expire
    local prefix = hostname..separator..info
    cache:set(prefix, upstream, expire)
end

_M.setGrayServer = function(self, grayServer)
    local cache = self.cache

    for k, v in  pairs(grayServer) do
        ngx.log(ngx.DEBUG,k,v)
        local ok, err = cache:set(k,v)
        if not ok then
            return false;
        end
    end
    return true
end

_M.setGrayServerSwitch = function(self,info,switch)
    local cache  = self.cache
    local expire = shdict_expire
    local ok, err = cache:set(info, switch, expire)
    if not ok then return false end
    return true
end

_M.getGrayServer = function(self, grayServerName)
    local cache = self.cache
    local switch   = cache:get(grayServerName)
    return switch
end


return _M
