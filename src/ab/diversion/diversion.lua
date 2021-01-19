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
local grayServerModule = require('abtesting.adapter.grayserver')

local globleConfig = require('config.appConf')
local divEnable = globleConfig.global_configs.divEnable

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

local grayServerPrefix = systemConf.prefixConf.graySwitchPrefix


local getRewriteInfo = function()
    return redirectInfo..ngx.var.backend
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
    if not host then
        return nil
    end
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
ngx.log(ngx.DEBUG,'host:',hostname)
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

-- loadGrayServer from cache or connectdb
local loadGrayServer = function()
    ngx.log(ngx.DEBUG,ngx.var.kv_gray)
    local grayServerCache  = cache:new(ngx.var.kv_gray)
    local url = ngx.var.uri;
    ngx.log(ngx.DEBUG,'请求路径:',url)
    local urls = utils.split(url,"/")
    local length = #urls
    local grayServerName
    if length>1 then
        for  i=1,#urls do
            grayServerName = urls[2]
            break
        end
    end
    ngx.log(ngx.DEBUG,'灰度服务名:',grayServerName)
    --step 1: read frome cache, but error
    local graySwitch = grayServerCache:getGrayServer(grayServerName)
    if not graySwitch then
        -- continue, then fetch from db
    elseif graySwitch == 'off' then
        return false, graySwitch,'grayServer not config , div switch off'
    end

    --step 2: acquire the lock
    local sem, err = sema:wait(0.01)
    if not sem then
        -- lock failed acquired
        -- but go on. This action just sets a fence
    end

    -- setp 3: read from cache again
    local graySwitch = grayServerCache:getGrayServer(grayServerName)
    ngx.log(ngx.DEBUG,"灰度服务:"..grayServerName,'开关:',graySwitch)

    if not graySwitch then
        -- continue, then fetch from db
    elseif graySwitch == 'off' then
        -- graySwitch = 0, div switch off, goto default upstream
        if sem then sema:post(1) end
        return false, graySwitch,'graySwitch == off, div switch off'
    else
        return true,graySwitch
    end

    -- step 4: fetch from redis
    local ok, db = connectdb(red, redisConf)
    if not ok then
        if sem then sema:post(1) end
        return ok, db
    end

    local grayMod = grayServerModule:new(db.redis, grayServerPrefix)
    local grayServer = grayMod:get(grayServerName)
    local graySwitch = 'on'
    if  not grayServer.name and not grayServer.switch then
        log:debug('fetch grayserver [', grayServerName, '] from redis db, get [nil]')
        grayServerCache:setGrayServerSwitch(grayServerName,graySwitch)
        return true,graySwitch
    else
        graySwitch = grayServer.switch
        grayServerCache:setGrayServerSwitch(grayServerName,graySwitch)
        if graySwitch == 'off' then
            return false, graySwitch
        end
    end
    ngx.log(ngx.DEBUG,"最后一步 ",grayServerName,"  ",graySwitch)

    if red then setKeepalive(red) end

    if sem then sema:post(1) end
    return true, graySwitch
end


-- getRuntimeInfo from cache or db
local pfunc = function()

    if not divEnable then
        return false,-1,nil
    end

--[[    local ok,status, graySwitch = xpcall(loadGrayServer,handler)
    --ngx.log(ngx.DEBUG,"  ",ok,"  ",status,"  ",graySwitch)

    if not ok then
        -- execute error, the type of status is table now
        log:errlog("get Gray Server\t", "error\t")
        return doerror(status, getRewriteInfo())
    else
        local info = 'get Gray Server error: '
        if  not status and graySwitch == 'off' then
            info = info .. 'graySwitch = off , div switch OFF'
            log:info(doredirect(info))
            return false,-1,nil
        end
    end]]


    local runtimeCache  = cache:new(ngx.var.sysConfig)
    --step 1: read frome cache, but error
    local divsteps = runtimeCache:getSteps(hostname)
    local runtimeStatus   = runtimeCache:getStatus(hostname)
    if not divsteps or not runtimeStatus then
        -- continue, then fetch from db
    elseif divsteps < 1 or runtimeStatus ==0 then
        -- divsteps = 0   , div switch off, goto default upstream
        return false, 'status == 0,divsteps < 1, div switchoff'
    else
        -- divsteps fetched from cache, then get Runtime From Cache
        local ok, runtimegroup = runtimeCache:getRuntime(hostname, divsteps)
        if ok then
            return true, divsteps, runtimegroup
            -- else fetch from db
        end
    end

    --step 2: acquire the lock
--[[    local sem, err = sema:wait(0.01)
    if not sem then
        -- lock failed acquired
        -- but go on. This action just sets a fence
    end]]

    -- setp 3: read from cache again
    local divsteps = runtimeCache:getSteps(hostname)
    local runtimeStatus   = runtimeCache:getStatus(hostname)
    if not divsteps or runtimeStatus then
        -- continue, then fetch from db
    elseif divsteps < 1 or runtimeStatus == 0 then
        -- divsteps = 0, div switch off, goto default upstream
        --if sem then sema:post(1) end
        return false, 'status ==0,divsteps < 1, div switchoff'
    else
        -- divsteps fetched from cache, then get Runtime From Cache
        local ok, runtimegroup = runtimeCache:getRuntime(hostname, divsteps)
        if ok then
            --if sem then sema:post(1) end
            return true, divsteps, runtimegroup
            -- else fetch from db
        end
    end

    -- step 4: fetch from redis
    local ok, db = connectdb(red, redisConf)
    if not ok then
        --if sem then sema:post(1) end
        return ok, db
    end

    local database      = db.redis
    local runtimeInfo   = getRuntime(database, hostname)

    local divsteps		= runtimeInfo.divsteps
    local runtimegroup	= runtimeInfo.runtimegroup
    local runtimeStatus = tonumber(runtimeInfo.status)

    runtimeCache:setRuntime(hostname, divsteps,runtimeStatus, runtimegroup)

    if runtimeStatus == 0 then
        return false,'status == 0, div switchoff'
    end

    if red then setKeepalive(red) end

    --if sem then sema:post(1) end

    return true, divsteps, runtimegroup
end




local ok, status, steps,runtimeInfo = xpcall(pfunc, handler)
--ngx.log(ngx.DEBUG," ",ok," ",status," ",steps)
if not ok then
    -- execute error, the type of status is table now
    log:errlog("get runtime\t", "error\t")
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
        else
            usertable[idx] = -1
        end
    end

	log:debug('usertable\t', cjson.encode(usertable))

--  usertable is empty, it seems that will never happen
--    if not next(usertable) then
--        return nil
--    end

    --step 1: read frome cache, but error
    log:debug("获取策略级数:"..divsteps)
    local upstable = upstreamCache:getUpstream(hostname,divsteps, usertable)
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
--[[    local sem, err = upsSema:wait(0.01)
    if not sem then
        -- lock failed acquired
        -- but go on. This action just set a fence for all but this request
    end]]

    -- setp 3: read from cache again
    local upstable = upstreamCache:getUpstream(hostname,divsteps, usertable)
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
            --if sem then upsSema:post(1) end
			local info = "get upstream ["..ups.."] according to [" ..idx.."] userinfo ["..usertable[idx].."] in cache 2"
            return ups, info
        end
    end

    -- step 4: fetch from redis
    local ok, db = connectdb(red, redisConf)
    if not ok then
        --if sem then upsSema:post(1) end
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
                upstreamCache:setUpstream(hostname,info, -1)
				log:debug('fetch userinfo [', info, '] from redis db, get [nil]')
            else
                --if sem then upsSema:post(1) end
                if red then setKeepalive(red) end

                upstreamCache:setUpstream(hostname,info, upstream)
				log:debug('fetch userinfo [', info, '] from redis db, get [', upstream, ']')

				local info = "get upstream ["..upstream.."] according to [" ..idx.."] userinfo ["..usertable[idx].."] in db"
                return upstream, info
            end
        end
    end

    --if sem then upsSema:post(1) end
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

if (upstream)  then
    ngx.var.backend = upstream
end



local info = doredirect(desc)
log:debug(info)
