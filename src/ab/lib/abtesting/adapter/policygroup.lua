---
-- @classmod abtesting.adapter.policy
-- @release 0.0.1
local modulename = "abtestingAdapterPolicyGroup"

local _M = { _VERSION = "0.0.1" }
local mt = { __index = _M }

local ERRORINFO     = require('abtesting.error.errcode').info
local policyModule  = require('abtesting.adapter.policy')
local fields        = require('abtesting.utils.init').fields
local utils         = require('abtesting.utils.utils')
local pageMod       = require('abtesting.utils.page')
local cjson         = require('cjson.safe')



local separator = ':'
---
-- policyIO new function
-- @param database opened redis.
-- @param baseLibrary a library(prefix of redis key) of policies.
-- @return runtimeInfoIO object
_M.new = function(self, database, groupLibrary, baseLibrary)
    if not database then
        error{ERRORINFO.PARAMETER_NONE, 'need avaliable redis db'}
    end
    if not baseLibrary then
        error{ERRORINFO.PARAMETER_NONE, 'need avaliable policy baselib'}
    end

    self.database     = database
    self.groupLibrary = groupLibrary
    self.baseLibrary  = baseLibrary
    self.idCountKey = table.concat({groupLibrary, fields.idCount}, separator)
    ngx.log(ngx.DEBUG,self.idCountKey) --debug redis
    local ok, err = database:exists(self.idCountKey)
    if not ok then error{ERRORINFO.REDIS_ERROR,  err} end

    if 0 == ok then
        local ok, err = database:set(self.idCountKey, '-1')
        if not ok then error{ERRORINFO.REDIS_ERROR, err} end
    end
    return setmetatable(self, mt)
end

---
-- get id for current policy
-- @return the id
_M.getIdCount = function(self)
    local database = self.database
    local key = self.idCountKey
    local idCount, err = database:incr(key)
    if not idCount then error{ERRORINFO.REDIS_ERROR, err} end

    return idCount
end

---
-- private function, set diversion type
-- @param id identify a policy
-- @param divtype diversion type (ipange/uid/...)
-- @return allways returned SUCCESS
_M._setDivtype = function(self, id, divtype)
    local database = self.database
    local key = table.concat({self.baseLibrary, id, fields.divtype}, separator)
    local ok, err = database:set(key, divtype)
    if not ok then error{ERRORINFO.REDIS_ERROR, err} end
end

---
-- private function, set diversion data
-- @param id identify a policy
-- @param divdata diversion data
-- @param modulename module name of diversion data (decision by diversion type)
-- @return allways returned SUCCESS
_M._setDivdata = function(self, id, divdata, modulename)
    local divModule = require(modulename)
    local database = self.database
    local key = table.concat({self.baseLibrary, id, fields.divdata}, separator)

    divModule:new(database, key):set(divdata)
end

_M.set = function(self, policyGroup)

    local database = self.database
    local baseLibrary = self.baseLibrary
    local policyMod = policyModule:new(database, baseLibrary)

    local steps = #policyGroup
    local group = {}
    for idx = 1, steps do
        local policy = policyGroup[idx]
        local id = policyMod:set(policy)
        group[idx] = id
    end

    local groupLibrary  = self.groupLibrary
    local groupid       = self:getIdCount()
    local groupKey      = table.concat({groupLibrary, groupid}, separator)
    ngx.log(ngx.DEBUG,"groupkey:"..groupKey) --debug groupKey when set
    database:init_pipeline()
    for idx = 1, steps do
        database:rpush(groupKey, group[idx])
    end
    local ok, err = database:commit_pipeline()
    if not ok then error{ERRORINFO.REDIS_ERROR, err} end

    local ret = {}
    ret.groupid = groupid
    ret.group = group

    return ret
end

_M.adminSet = function(self, policyGroup)

    local database = self.database
    local baseLibrary = self.baseLibrary

    local steps = #policyGroup
    local group = {}
    for idx = 1, steps do
        local policy = policyGroup[idx]
        group[idx] = policy
    end

    local groupLibrary  = self.groupLibrary
    local groupid       = self:getIdCount()
    local groupKey      = table.concat({groupLibrary, groupid}, separator)
    ngx.log(ngx.DEBUG,"groupkey:"..groupKey) --debug groupKey when set
    database:init_pipeline()
    for idx = 1, steps do
        database:rpush(groupKey, group[idx])
    end
    local ok, err = database:commit_pipeline()
    if not ok then error{ERRORINFO.REDIS_ERROR, err} end

    local ret = {}
    ret.groupid = groupid
    ret.group = group

    return ret
end


_M.check = function(self, policyGroup)

    local steps = #policyGroup
    local policyMod = policyModule:new(self.database, self.baseLibrary)
    for idx = 1, steps do
        local policy    = policyGroup[idx]
        local chkinfo   = policyMod:check(policy)
        local valid = chkinfo[1]
        local info  = chkinfo[2]
        local desc  = chkinfo[3]
        if not valid then
            local extra = 'policy NO.'..idx..' ' 
            if not desc then
                desc = extra .. 'not valid'
            else
                desc = extra .. desc 
            end
            return {valid, info, desc}
        end
    end
    return {true}
end

---
-- delete a policy from specified redis lib
-- @param id the policy identify
-- @return allways returned SUCCESS
_M.del = function(self, id)
    local database      = self.database
    local groupLibrary  = self.groupLibrary

    local groupKey      = table.concat({groupLibrary, id}, separator)

    local group, err = database:lrange(groupKey, 0, -1)
    if not group or type(group) ~= 'table' then 
        error{ERRORINFO.REDIS_ERROR, err} 
    end

    local tmpkeys  = {}
    local idx   = 0
    for _, policyid in pairs(group) do
        idx = idx + 1

        local policyLib = table.concat({self.baseLibrary, policyid}, separator)
        local keys, err = database:keys(policyLib..'*')
        if not keys then error{ERRORINFO.REDIS_ERROR, err} end

        tmpkeys[idx] = keys
    end

    database:init_pipeline()
    for _, v in pairs(tmpkeys) do
        for _, vv in pairs(v) do
            database:del(vv)
        end
    end
    database:del(groupKey)

    local ok, err = database:commit_pipeline()
    if not ok then error{ERRORINFO.REDIS_ERROR, err} end
end

_M.get = function(self, id)

    local database = self.database
    local groupLibrary  = self.groupLibrary
    local groupKey      = table.concat({groupLibrary, id}, separator)

    local group, err = database:lrange(groupKey, 0, -1)
    if not group or type(group) ~= 'table' then 
        error{ERRORINFO.REDIS_ERROR, err} 
    end

    local ret = {}
    ret.groupid = id
    ret.group = group

    return ret
end

_M.list = function(self)
    local database = self.database
    local groupLibrary  = self.groupLibrary
    local groupKey      = table.concat({groupLibrary, '*'}, separator)

    local idCountKey =  table.concat({groupLibrary, fields.idCount}, separator)

    local group, err = database:keys(groupKey)
    if not group or type(group) ~= 'table' then
        error{ERRORINFO.REDIS_ERROR, err}
    end

    local groupList = {}
    local k=1
    for i=1,#group do
        if group[i] == idCountKey then
            --continue
        else
            groupList[k] = group[i]
            k = k+1
        end
    end
    local ret = {}
    for i=1,#groupList do

        local result = {}
        local groupKey = groupList[i]
        local ids = utils.split(groupKey,separator)
        local id = ids[3]
        local groups, err = database:lrange(groupList[i], 0, -1)
        if not groups or type(groups) ~= 'table' then
            error{ERRORINFO.REDIS_ERROR, err}
        end
        result.id = id
        result.groups = groups
        ret[i] = result
    end

    return ret
end

_M.pageList = function(self,page,size)
    local database = self.database
    local groupLibrary  = self.groupLibrary
    local groupKey      = table.concat({groupLibrary, '*'}, separator)

    local idCountKey =  table.concat({groupLibrary, fields.idCount}, separator)

    local page = page or 1
    local size = size or 20
    local startIndex = (page-1)*size + 1
    local endIndex = page*size

    local group, err = database:keys(groupKey)
    if not group or type(group) ~= 'table' then
        error{ERRORINFO.REDIS_ERROR, err}
    end

    local groupList = {}
    local k=1
    for i=1,#group do
        if group[i] == idCountKey then
            --continue
        else
            groupList[k] = group[i]
            k = k+1
        end
    end
    local ret = {}
    for i=1,#groupList do

        local result = {}
        local groupKey = groupList[i]
        local ids = utils.split(groupKey,separator)
        local id = ids[3]
        local groups, err = database:lrange(groupList[i], 0, -1)
        if not groups or type(groups) ~= 'table' then
            error{ERRORINFO.REDIS_ERROR, err}
        end
        result.id = id
        result.groups = groups
        ret[i] = result
    end

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
