local modulename = "abtestingInit"
local _M = {}

_M._VERSION = '0.0.1'

--[[_M.redisConf = {
    ["uds"]      = ngx.var.redis_uds,
    ["host"]     = ngx.var.redis_host,
    ["port"]     = ngx.var.redis_port,
    ["poolsize"] = ngx.var.redis_pool_size,
    ["idletime"] = ngx.var.redis_keepalive_timeout , 
    ["timeout"]  = ngx.var.redis_connect_timeout,
    ["dbid"]     = ngx.var.redis_dbid,
    ["auth"]     = ngx.var.redis_auth
}]]

_M.redisConf = {
    ["uds"]      = '/tmp/redis.sock',
    ["host"]     = '172.18.5.110',
    ["port"]     = '6379',
    ["poolsize"] = 20000,
    ["idletime"] = 90000 ,
    ["timeout"]  = 3000,
    ["dbid"]     = 0,
    ["auth"]     = 'Yq0wHk5AmlpJ0lEleO5zsMNN6npXOQ'
}

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
    ["default_backend"]     = ngx.var.default_backend,
    --["shdict_expire"]       = 60,   -- in s
    ["shdict_expire"]       = tonumber(ngx.var.shdict_expire or 60)
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
