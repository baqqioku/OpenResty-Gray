local modulename = "abtestingInit"
local _M = {}

local globalConfig = require('config.appConf')
local redisConf = globalConfig.redisConf
local divConf = globalConfig.divConf


_M._VERSION = '0.0.1'

_M.redisConf = {
    --["uds"]      = ngx.var.redis_uds,
    ["host"]     = ngx.var.redis_host,
    ["port"]     = ngx.var.redis_port,
    ["poolsize"] = ngx.var.redis_pool_size,
    ["idletime"] = ngx.var.redis_idletime ,
    ["timeout"]  = ngx.var.redis_connect_timeout,
    ["dbid"]     = ngx.var.redis_dbid,
    ["auth"]     = ngx.var.redis_auth
}
--[[
_M.redisConf = {
    --["uds"]      = redisConf.uds,
    ["host"]     = redisConf.host,
    ["port"]     = redisConf.port,
    ["poolsize"] = redisConf.poolsize,
    ["idletime"] = redisConf.idletime ,
    ["timeout"]  = redisConf.timeout,
    ["dbid"]     = redisConf.dbid,
    ["auth"]     = redisConf.auth
}]]

_M.divtypes = {
    ["iprange"]     = 'ipParser',  
    ["uidrange"]    = 'uidParser',
    ["uidsuffix"]   = 'uidParser',
    ["uidappoint"]  = 'uidParser',
    ["arg_city"]    = 'cityParser',
    ["url"]         = 'urlParser',
    ["token"]       = 'tokenParser',
    ["version"]     = 'versionParser',
    ["flowratio"]   =  'flowRatioParser'
}

_M.divtypeNames = {
    ["iprange"]     = 'ip范围',
    ["uidsuffix"]   = 'id后缀',
    ["uidappoint"]  = '白名单',
    ["arg_city"]    = '城市区域',
    ["url"]         = 'url地址',
    ["token"]       = 'token解析',
    ["version"]     = '版本',
    ["flowratio"]   =  '流量比例'
}

_M.prefixConf = {
    ["policyLibPrefix"]     = 'ab:policies',
    ["policyGroupPrefix"]   = 'ab:policygroups',
    ["runtimeInfoPrefix"]   = 'ab:runtimeInfo',
    ["graySwitchPrefix"]    = 'ab:grayserver',
    ["domainname"]          = ngx.var.domain_name
}

_M.divConf = {
    ["default_backend"]     = divConf.default_backend,
    --["shdict_expire"]       = 60,   -- in s
    ["shdict_expire"]       = divConf.shdict_expire
}

_M.cacheConf = {
    ['timeout']             = ngx.var.lock_expire,
    ['runtimeInfoLock']     = ngx.var.rt_cache_lock,
    ['upstreamLock']        = ngx.var.up_cache_lock,
}

_M.indices = {
    'first', 'second', 'third',
    'forth', 'fifth', 'sixth', 
    'seventh', 'eighth', 'ninth'
}

_M.fields = {
    ['divModulename']       = 'divModulename',           
    ['divDataKey']          = 'divDataKey',
    ['userInfoModulename']  = 'userInfoModulename',
    ['divtype']             = 'divtype',
    ['divdata']             = 'divdata',
    ['idCount']             = 'idCount',
    ['divsteps']            = 'divsteps',
    ['status']              = 'status'
}

_M.loglv = {

    ['err']					= ngx.ERR, 
	['info']				= ngx.INFO,
    ['warn']				= ngx.WARN,
    ['debug']				= ngx.DEBUG
}






return _M
