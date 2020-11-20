local modulename = "abtestingDiversionToken"

local _M    = {}
local mt    = { __index = _M }
_M._VERSION = "0.0.1"

local ERRORINFO	= require('abtesting.error.errcode').info

local k_tokenset  = 'tokenset'
local k_upstream= 'upstream'

_M.new = function(self, database, policyLib)
    if not database then
        error{ERRORINFO.PARAMETER_NONE, 'need avaliable redis db'}
    end if not policyLib then
        error{ERRORINFO.PARAMETER_NONE, 'need avaliable policy lib'}
    end
    
    self.database = database
    self.policyLib = policyLib
    return setmetatable(self, mt)
end

local isNULL = function(v)
    return v and v ~= ngx.null
end

--	policy is in format as {{upstream = '192.132.23.125', tokenset ={ 214214, 23421,12421} }, {}}
_M.check = function(self, policy)
    for _, v in pairs(policy) do
        local tokenset    = v[k_tokenset]
        local upstream  = v[k_upstream]
        
        local v_tokenset    = tokenset and (type(tokenset) == 'table')
        local v_upstream  = upstream and upstream ~= ngx.null
        
        if not v_tokenset or not v_upstream then
            local info = ERRORINFO.POLICY_INVALID_ERROR 
            local desc = ' k_tokenset or k_upstream error'
            return {false, info, desc}
        end
        
        for _, uid in pairs(tokenset) do
            if not tostring(uid) then
                local info = ERRORINFO.POLICY_INVALID_ERROR 
                local desc = 'token invalid '
                return {false, info, desc}
            end
        end
        --TODO: need to check upstream alive
    end
    
    return {true}
end

--	policyData will be in hash table  uid:upstream
_M.set = function(self, policy)
    local database  = self.database 
    local policyLib = self.policyLib
    
    database:init_pipeline()
    for _, v in pairs(policy) do
        local tokenset   = v[k_tokenset]
        local upstream = v[k_upstream] 
        for _, uid in pairs(tokenset) do
            database:hset(policyLib, uid, upstream)
        end
    end
    local ok, err = database:commit_pipeline()
    if not ok then 
        error{ERRORINFO.REDIS_ERROR, err} 
    end
end

_M.get = function(self)
    local database  = self.database 
    local policyLib = self.policyLib
    --ngx.log(INFO,)
    local data, err = database:hgetall(policyLib)
    if not data then 
        error{ERRORINFO.REDIS_ERROR, err} 
    end

    return data
end

_M.getUpstream = function(self, uid)
    if not uid then
        return nil
    end
    
    local database, key = self.database, self.policyLib
    
    local backend, err = database:hget(key, uid)
    if not backend then error{ERRORINFO.REDIS_ERROR, err} end
    
    if backend == ngx.null then backend = nil end
    
    return backend
end

return _M
