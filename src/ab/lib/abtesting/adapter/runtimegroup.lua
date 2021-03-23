---
-- @classmod abtesting.adapter.runtime
-- @release 0.0.1
local modulename = "abtestingAdapterRuntimeGroup"

local _M = {}
local metatable = {__index = _M}

_M._VERSION = "0.0.1"

local ERRORINFO         = require('abtesting.error.errcode').info
local runtimeModule     = require('abtesting.adapter.runtime')
local systemConf        = require('abtesting.utils.init')
local policyModule      = require('abtesting.adapter.policy')
local policyGroupModule = require('abtesting.adapter.policygroup')
local utils         = require('abtesting.utils.utils')
local cjson         = require('cjson.safe')
local pageMod       = require('abtesting.utils.page')



local prefixConf        = systemConf.prefixConf
local divtypes          = systemConf.divtypes
local policyLib         = prefixConf.policyLibPrefix
local policyGroupLib    = prefixConf.policyGroupPrefix
local indices           = systemConf.indices 
local fields            = systemConf.fields

local separator = ':'

---
-- runtimeInfoIO new function
-- @param database  opened redis
-- @param baseLibrary a library(prefix of redis key) of runtime info
-- @return runtimeInfoIO object
_M.new = function(self, database, baseLibrary)
	if not database then
		error{ERRORINFO.PARAMETER_NONE, 'need a object of redis'}
	end if not baseLibrary then
	    error{ERRORINFO.PARAMETER_NONE, 'need a library of runtime info'}
    end

    self.database     = database
    self.baseLibrary  = baseLibrary

    return setmetatable(self, metatable)
end

---
-- set runtime info(diversion modulename and diversion metadata key)
-- @param domain is a domain name to search runtime info
-- @param ... now is diversion modulename and diversion data key
-- @return if returned, the return value always SUCCESS
_M.set = function(self, domain, policyGroupId, divsteps)
    local database = self.database
    local baseLibrary = self.baseLibrary
    local prefix = baseLibrary .. ':' .. domain

    local policyGroupMod = policyGroupModule:new(database, policyGroupLib, policyLib)
    local policyGroup = policyGroupMod:get(policyGroupId)
    local groupid = policyGroup.groupid
    local group = policyGroup.group

--  添加 group为空错误
    if #group < 1 then
        error{ERRORINFO.PARAMETER_TYPE_ERROR, 'blank policyGroupId'}
    end

    if divsteps and divsteps > #group then  
        error{ERRORINFO.PARAMETER_TYPE_ERROR, 'divsteps is deeper than policyGroupID'}
    end

    if not divsteps then divsteps = #group end

    for i = 1, divsteps do
        local idx = indices[i]
        local policyId = group[i]

        local policyMod = policyModule:new(database, policyLib)
        local policy = policyMod:get(policyId)

        local divtype = policy.divtype
        local divdata = policy.divdata
        if divtype == ngx.null or
            divdata == ngx.null then
            error{ERRORINFO.POLICY_BLANK_ERROR, 'policy NO.'..policyId}
        end

        --        if not divtypes[divtype] then
        --            -- unsupported divtype
        --        end

        local divModulename     = table.concat({'abtesting', 'diversion', divtype}, '.')
        local divDataKey        = table.concat({policyLib, policyId, fields.divdata}, ':')
        local userInfoModulename= table.concat({'abtesting', 'userinfo', divtypes[divtype]}, '.')

        local runtimeMod = runtimeModule:new(database, prefix) 
        runtimeMod:set(idx, divModulename, divDataKey, userInfoModulename)
    end
    
    local divStep = prefix .. ':' .. fields.divsteps
    local statusKey = prefix..separator..fields.status
    local groupKey = prefix..separator..fields.group
    local ok,err  = database:set(divStep, divsteps)
    local ok1,err = database:set(statusKey,1)
    local ok2,err = database:set(groupKey,policyGroupId)
    if not ok or not ok1 or not ok2 then  error{ERRORINFO.REDIS_ERROR, err} end

    return ERRORINFO.SUCCESS
end

---
-- get runtime info(diversion modulename and diversion metadata key)
-- @param domain is a domain name to search runtime info
-- @return a table of diversion modulename and diversion metadata key
_M.get = function(self, domain)
    local database = self.database
    local baseLibrary = self.baseLibrary
    local prefix = baseLibrary .. ':' .. domain

    local ret = {}

    local divStep = prefix .. ':' .. fields.divsteps
    ngx.log(ngx.DEBUG,divStep..'  ',domain)
    local ok, err = database:get(divStep)
    if not ok then error{ERRORINFO.REDIS_ERROR, err} end

    local divsteps = tonumber(ok)
    if not divsteps then
        ret.divsteps = 0
        ret.runtimegroup = {}
        return ret
    end

    local status = prefix .. ':' .. fields.status
    local singleKey = prefix .. ':' .. fields.single
    local groupKey =  prefix .. ':' .. fields.group
    ngx.log(ngx.DEBUG,status..'  ',domain)
    local ok, err = database:get(status)
    local ok1, err = database:get(singleKey)
    local ok2,err = database:get(groupKey)
    if not ok or not ok1 or not ok2 then
        error{ERRORINFO.REDIS_ERROR, err}
    elseif ok == ngx.null then
        ok = 1
    end

    if ok1 == ngx.null then
        ok1 = ''
    end

    if ok2 == ngx.null then
        ok2 = ''
    end

    local runtimeStatus = tonumber(ok)

    local runtimeGroup = {}
    for i = 1, divsteps do
        local idx = indices[i]
        local runtimeMod    =  runtimeModule:new(database, prefix)
        local runtimeInfo   =  runtimeMod:get(idx)
        local rtInfo   = {}
        rtInfo[fields.divModulename]      = runtimeInfo[1]
        rtInfo[fields.divDataKey]         = runtimeInfo[2]
        rtInfo[fields.userInfoModulename] = runtimeInfo[3]

        runtimeGroup[idx] = rtInfo
    end
    ret.status = runtimeStatus
    ret.divsteps = divsteps
    ret.runtimegroup = runtimeGroup
    ret.single = ok1
    ret.group = ok2
    return ret

end

---
-- delete runtime info(diversion modulename and diversion metadata key)
-- @param domain a domain of delete
-- @return if returned, the return value always SUCCESS
_M.del = function(self, domain)
    local database = self.database
    local baseLibrary = self.baseLibrary
    local prefix = baseLibrary .. ':' .. domain

    local divStep = prefix .. ':' .. fields.divsteps
    local status = prefix .. ':' .. fields.status
    local singleKey = prefix .. ':' .. fields.single
    local groupKey = prefix .. ':' .. fields.group
    ngx.log(ngx.DEBUG," del divStep:"..divStep)
    local ok, err = database:get(divStep)
    if not ok then error{ERRORINFO.REDIS_ERROR, err} end

    local divsteps = tonumber(ok)
    if not divsteps or divsteps == ngx.null or divsteps == null then
        local ok, err = database:del(divStep)
        if not ok then error{ERRORINFO.REDIS_ERROR, err} end
        return nil
    end

    for i = 1, divsteps do
        local idx = indices[i]
        local runtimeMod =  runtimeModule:new(database, prefix)
        local ok, err = runtimeMod:del(idx)
        if not ok then error{ERRORINFO.REDIS_ERROR, err} end
    end

    local ok, err = database:del(divStep)
    local ok1,err = database:del(status)
    local ok2,err = database:del(singleKey)
    local ok3,err = database:del(groupKey)
    if not ok and not ok1 and not ok2 and not ok3 then error{ERRORINFO.REDIS_ERROR, err} end
end

_M.list = function(self)
    local database = self.database
    local baseLibrary = self.baseLibrary
    local allRuntime,err = database:keys(baseLibrary..'*')
    local ret = {}
    if not allRuntime then
        return ret
    end
    local domainList = {}
    local i=1

    for k,v in ipairs(allRuntime) do
        local strList = utils.split(v,":")
        local prefixStatusKey  = baseLibrary..separator..strList[3]..separator..fields.status
        ngx.log(ngx.DEBUG,prefixStatusKey,'xxxx--',v)
        if #strList>4 then
            -- continue
        elseif prefixStatusKey == v then
            --continue
        else
            domainList[i] = v
            i = i+1;
        end
    end

    local divStepList = {}
    local realDomainList = {}
    if #domainList >0 then
        for k,v in ipairs(domainList) do
            local str = utils.split(v,":")
            realDomainList[k] = str[3]
            local ok, err = database:get(v)
            if not ok then error{ERRORINFO.REDIS_ERROR, err} end
            local divstepsDomain = tonumber(ok)
            divStepList[str[3]] = divstepsDomain
        end
    end

    local i=1
    for k,v in ipairs(realDomainList) do
        local model = {}
        local _domain = v
        model.domain = _domain
        local prefix = baseLibrary .. ':' .. _domain
        local divSteps = divStepList[_domain]
        local modelNames = {}
        local policys = {}

        local statusKey = table.concat({prefix, fields.status}, separator)
        local ok,err = database:get(statusKey)
        if not ok or ok == ngx.null or ok == null then
            model.status = 1
        else
            model.status = ok
        end

        for i = 1, divSteps do
            local idx = indices[i]
            local divModulenameKey      = table.concat({prefix, idx, fields.divModulename}, separator)
            local divDataKey = table.concat({prefix, idx, fields.divDataKey}, separator)
            local ok,err = database:get(divModulenameKey)

            if ok then
                local divtype = utils.split2(ok,".")[3]
                modelNames[i] = divtype
            end

            local ok,err = database:get(divDataKey)
            if ok then
                local policyId = utils.split2(ok,":")[3]
                policys[i] = policyId
            end

        end
        model.divtypes = modelNames
        model.policys = policys

        ret[k] = model
    end
    ngx.log(ngx.DEBUG,cjson.encode(ret))
    table.sort(ret, function(n1, n2)
        return tonumber(n1['policys'][1]) < tonumber(n2['policys'][1])
    end)

    ngx.log(ngx.DEBUG,cjson.encode(ret))
    return ret;
end


_M.pageList = function(self,page,size)
    local database = self.database
    local baseLibrary = self.baseLibrary
    local allRuntime,err = database:keys(baseLibrary..'*')

    local page = page or 1
    local size = size or 20
    local startIndex = (page-1)*size + 1
    local endIndex = page*size

    local ret = {}
    if not allRuntime then
        return ret
    end

    ngx.log(ngx.DEBUG,cjson.encode(allRuntime))


    local domainList = {}
    local i=1
    for k,v in ipairs(allRuntime) do
        local strList = utils.split(v,":")
        local prefixStatusKey  = baseLibrary..separator..strList[3]..separator..fields.status
        local prefixSingleKey  = baseLibrary..separator..strList[3]..separator..fields.single
        local prefixGroupKey  = baseLibrary..separator..strList[3]..separator..fields.group

        ngx.log(ngx.DEBUG,v)
        if #strList>4 then
            -- continue
        elseif prefixStatusKey == v or prefixSingleKey==v or prefixGroupKey == v then
            --continue
        else
            domainList[i] = v
            i = i+1;
        end
    end

    local divStepList = {}
    local realDomainList = {}

    if #domainList >0 then
        for k,v in ipairs(domainList) do
            local str = utils.split(v,":")
            realDomainList[k] = str[3]
            local ok, err = database:get(v)
            if not ok then error{ERRORINFO.REDIS_ERROR, err} end
            local divstepsDomain = tonumber(ok)
            divStepList[str[3]] = divstepsDomain
        end
    end

    local i=1
    for k,v in ipairs(realDomainList) do
        local model = {}
        local _domain = v
        model.domain = _domain
        local prefix = baseLibrary .. ':' .. _domain
        local divSteps = divStepList[_domain]

        local statusKey = table.concat({prefix, fields.status}, separator)
        local ok,err = database:get(statusKey)
        if not ok or ok == ngx.null or ok == null then
            model.status = 1
        else
            model.status = ok
        end

        local modelNames = {}
        local policys = {}
        for i = 1, divSteps do
            local idx = indices[i]

            local divModulenameKey      = table.concat({prefix, idx, fields.divModulename}, separator)
            local divDataKey = table.concat({prefix, idx, fields.divDataKey}, separator)
            local ok,err = database:get(divModulenameKey)

            if ok then
                local divtype = utils.split2(ok,".")[3]
                modelNames[i] = divtype
            end

            local ok,err = database:get(divDataKey)
            if ok then
                local policyId = utils.split2(ok,":")[3]
                policys[i] = policyId
            end

        end
        model.divtypes = modelNames
        model.policys = policys
        ret[k] = model
    end

    table.sort(ret, function(n1, n2) return tonumber(n1['policys'][1]) < tonumber(n2['policys'][1]) end)

    local maxIndex = #ret
    if endIndex > maxIndex then
        endIndex = maxIndex
    end
    local k = 1
    local result = {}
    for i=startIndex,endIndex do
        result[k] = ret[i]
        k = k +1
    end

    local pageMod = pageMod:new(page,size,#ret,result)
    local page = pageMod:page()
    ngx.log(ngx.DEBUG,cjson.encode(page))
    return page
end


return _M
