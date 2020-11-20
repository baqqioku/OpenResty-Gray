local runtimeModule = require('abtesting.adapter.runtimegroup')
local redisModule   = require('abtesting.utils.redis')
local systemConf    = require('abtesting.utils.init')
local utils         = require('abtesting.utils.utils')
local logmod	   	= require("abtesting.utils.log")
local cache         = require('abtesting.utils.cache')
local handler	    = require('abtesting.error.handler').handler
local ERRORINFO	    = require('abtesting.error.errcode').info
local cjson         = require('cjson.safe')
local semaphore     = require("abtesting.utils.sema")

local dolog         = utils.dolog	
local doerror       = utils.doerror

local redisConf	    = systemConf.redisConf
local prefixConf    = systemConf.prefixConf
local indices       = systemConf.indices
local fields        = systemConf.fields
local runtimeLib    = prefixConf.runtimeInfoPrefix
local redirectInfo  = 'proxypass to upstream http://'

local sema          = semaphore.sema
local upsSema       = semaphore.upsSema

local upstream      = nil
local flowRatiostrategyCache = ngx.shared.api_flow_ratio_strategy





local getRewriteInfo = function()
    return redirectInfo..ngx.var.backend
end

local getGraySwitch = function()
    local isGray = ngx.var.gray
    ngx.log(ngx.DEBUG,"灰度开关:",isGray)
    return isGray
end


local doredirect = function(info)
    local ok  = ERRORINFO.SUCCESS
    local err = redirectInfo..ngx.var.backend
    return dolog(ok, err, info)
end

local setKeepalive = function(red)
    local ok, err = red:keepalivedb()
    if not ok then
        local errinfo = ERRORINFO.REDIS_KEEPALIVE_ERROR
        local errdesc = err
        dolog(errinfo, errdesc)
        return
    end
end

local getHost = function()
    local host = ngx.req.get_headers()['Host']
    if not host then return nil end
    local hostkey = ngx.var.hostkey
    if hostkey then
        return hostkey
    else
        --location 中不配置hostkey时
        return host
    end
end

local getRuntime = function(database, hostname)
    local runtimeMod = runtimeModule:new(database, runtimeLib)
    return runtimeMod:get(hostname)
end

local getUserInfo = function(runtime)
    local userInfoModname = runtime[fields.userInfoModulename]
    ngx.log(ngx.DEBUG,"用户模块:userInfoModname: "..userInfoModname)
    local userInfoMod     = require(userInfoModname)
    local userInfo        = userInfoMod:get()
    return userInfo
end

local getUpstream = function(runtime, database, userInfo)
    local divModname = runtime[fields.divModulename]
    ngx.log(ngx.DEBUG,"devModname: ",divModname)
    local policy     = runtime[fields.divDataKey]
    ngx.log(ngx.DEBUG,"policy: ",policy)
    local divMod     = require(divModname)
    local divModule  = divMod:new(database, policy)
    ngx.log(ngx.DEBUG,"info: ",userInfo)
    local upstream   = divModule:getUpstream(userInfo)

    return upstream
end

local connectdb = function(red, redisConf)
    if not red then
        red = redisModule:new(redisConf)
    end
    local ok, err = red:connectdb()
    if not ok then
        local info = ERRORINFO.REDIS_CONNECT_ERROR
        dolog(info, err)
        return false, err
    end

    return ok, red
end

local hostname = getHost()
if not hostname then
    local info = ERRORINFO.ARG_BLANK_ERROR
    local desc = 'cannot get [Host] from req headers'
    dolog(info, desc, getRewriteInfo())
    return nil
end

--[[local prefix = hostname
flowRatiostrategyCache:set(prefix .. "_count",0)
ngx.log(ngx.INFO, "timer_at run worker:",ngx.worker.id())]]

local log = logmod:new(hostname)

local red = redisModule:new(redisConf)

-- getRuntimeInfo from cache or db
local pfunc = function()

    local runtimeCache  = cache:new(ngx.var.sysConfig)

    --step 1: read frome cache, but error
    local divsteps = runtimeCache:getSteps(hostname)
    if not divsteps then
        -- continue, then fetch from db
    elseif divsteps < 1 then
        -- divsteps = 0, div switch off, goto default upstream
        return false, 'divsteps < 1, div switchoff'
    else
     -- divsteps fetched from cache, then get Runtime From Cache
        local ok, runtimegroup = runtimeCache:getRuntime(hostname, divsteps)
        if ok then
            return true, divsteps, runtimegroup
        -- else fetch from db
        end
    end

    --step 2: acquire the lock
    local sem, err = sema:wait(0.01)
    if not sem then
        -- lock failed acquired
        -- but go on. This action just sets a fence
    end

    -- setp 3: read from cache again
    local divsteps = runtimeCache:getSteps(hostname)
    if not divsteps then
        -- continue, then fetch from db
    elseif divsteps < 1 then
        -- divsteps = 0, div switch off, goto default upstream
        if sem then sema:post(1) end
        return false, 'divsteps < 1, div switchoff'
    else
     -- divsteps fetched from cache, then get Runtime From Cache
        local ok, runtimegroup = runtimeCache:getRuntime(hostname, divsteps)
        if ok then
            if sem then sema:post(1) end
            return true, divsteps, runtimegroup
        -- else fetch from db
        end
    end

    -- step 4: fetch from redis
    local ok, db = connectdb(red, redisConf)
    if not ok then
        if sem then sema:post(1) end
		return ok, db
    end

    local database      = db.redis
    local runtimeInfo   = getRuntime(database, hostname)

    local divsteps		= runtimeInfo.divsteps
    local runtimegroup	= runtimeInfo.runtimegroup

    runtimeCache:setRuntime(hostname, divsteps, runtimegroup)
    if red then setKeepalive(red) end

    if sem then sema:post(1) end
    return true, divsteps, runtimegroup
end

local ok, status, steps, runtimeInfo = xpcall(pfunc, handler)
if not ok then
    -- execute error, the type of status is table now
    log:errlog("getruntime\t", "error\t")
    return doerror(status, getRewriteInfo())
else
	local info = 'getRuntimeInfo error: '
	if not status or not steps or steps < 1 then
		if not status then
			local reason = steps
			if reason then
				info = info .. reason
			end
		elseif not steps then
			info = info .. 'no divsteps, div switch OFF'
		elseif steps < 1 then
			info = info .. 'divsteps < 1, div switch OFF'
		end
		return log:info(doredirect(info))
	else
		log:debug('divstep = ', steps, ' runtimeinfo = ', cjson.encode(runtimeInfo))
	end
end

local divsteps      = steps
local runtimegroup  = runtimeInfo

local upPfunc = function()

    local upstreamCache = cache:new(ngx.var.kv_upstream)

    local usertable = {}
    for i = 1, divsteps do
        local idx = indices[i]
        log:debug("idx:",idx)
        local runtime = runtimegroup[idx]
        if runtime then
            log:debug("runtime:",cjson.encode(runtime))
        end

        local info = getUserInfo(runtime) --获取 实际的 id 策略lua解析器 如  abtesting.userinfo.uidParser 在调用get 方法获取解析参数

        if info then
            log:debug('获取路由解析参数: ', cjson.encode(info))
        end

        if info and info ~= '' then
            usertable[idx] = info
        end
    end

	log:debug('userinfo\t', cjson.encode(usertable))


--  usertable is empty, it seems that will never happen
--    if not next(usertable) then
--        return nil
--    end

    --step 1: read frome cache, but error
    log:debug("获取策略级数:"..divsteps)
    local upstable = upstreamCache:getUpstream(divsteps, usertable)
	log:debug('first fetch: upstable in cache ', cjson.encode(upstable))
    for i = 1, divsteps do
        local idx = indices[i]
        local ups = upstable[idx]
        if ups == -1 then
			if i == divsteps then
				local info = "usertable has no upstream in cache 1, proxypass to default upstream"
				log:info(info)
				return nil, info
			end
            -- continue
        elseif ups == nil then
			-- why to break
			-- the reason is that maybe some userinfo is empty
			-- 举例子,用户请求
			-- location/div -H 'X-Log-Uid:39' -H 'X-Real-IP:192.168.1.1'
			-- 分流后缓存中 39->-1, 192.168.1.1-> beta2
			-- 下一请求：
			-- location/div?city=BJ -H 'X-Log-Uid:39' -H 'X-Real-IP:192.168.1.1'
			-- 该请求应该是  39-> -1, BJ->beta1, 192.168.1.1->beta2，
			-- 然而cache中是 39->-1, 192.168.1.1->beta2，
			-- 如果此分支不break的话，将会分流到beta2上，这是错误的。

            break
        else
			local info = "get upstream ["..ups.."] according to [" ..idx.."] userinfo ["..usertable[idx].."] in cache 1"
			log:info(info)
            return ups, info
        end
    end

    --step 2: acquire the lock
    local sem, err = upsSema:wait(0.01)
    if not sem then
        -- lock failed acquired
        -- but go on. This action just set a fence for all but this request
    end

    -- setp 3: read from cache again
    local upstable = upstreamCache:getUpstream(divsteps, usertable)
	log:debug('second fetch: upstable in cache\t', cjson.encode(upstable))
    for i = 1, divsteps do
        local idx = indices[i]
        local ups = upstable[idx]
        if ups == -1 then
            -- continue
			if i == divsteps then
				local info = "usertable has no upstream in cache 2, proxypass to default upstream"
				return nil, info
			end

        elseif ups == nil then
			-- do not break, may be the next one will be okay
             break
        else
            if sem then upsSema:post(1) end
			local info = "get upstream ["..ups.."] according to [" ..idx.."] userinfo ["..usertable[idx].."] in cache 2"
            return ups, info
        end
    end

    -- step 4: fetch from redis
    local ok, db = connectdb(red, redisConf)
    if not ok then
        if sem then upsSema:post(1) end
		return nil, db
    end
    local database = db.redis

    for i = 1, divsteps do
        local idx = indices[i]
        local runtime = runtimegroup[idx]
        local info = usertable[idx]

        if info then
            --缓存找不到 ，这里 请求了策略 getUpstream()，从redis读取
            local upstream = getUpstream(runtime, database, info)
            if not upstream then
                upstreamCache:setUpstream(info, -1)
				log:debug('fetch userinfo [', info, '] from redis db, get [nil]')
            else
                if sem then upsSema:post(1) end
                if red then setKeepalive(red) end

                upstreamCache:setUpstream(info, upstream)
				log:debug('fetch userinfo [', info, '] from redis db, get [', upstream, ']')

				local info = "get upstream ["..upstream.."] according to [" ..idx.."] userinfo ["..usertable[idx].."] in db"
                return upstream, info
            end
        end
    end

    if sem then upsSema:post(1) end
    if red
        then setKeepalive(red)
    end
    return nil, 'the req has no target upstream'
end

local status, info, desc = xpcall(upPfunc, handler)
--log:info('----------------------------')
--ngx.log(ngx.DEBUG,"status:",status," info: ",cjson.decode(info)," desc:",desc)
if not status then
    doerror(info)
else
    upstream = info
end

local isGray = ngx.var.gray
ngx.log(ngx.DEBUG,type(ngx.var.gray))
ngx.log(ngx.DEBUG,"灰度开关:",ngx.var.gray)

if (upstream and isGray)  then
    ngx.var.backend = upstream
end

local info = doredirect(desc)
log:errlog(info)
