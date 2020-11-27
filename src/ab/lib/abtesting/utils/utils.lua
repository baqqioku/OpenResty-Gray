local modulename = "abtestingUtils"
local _M = {}
_M._VERSION = '0.0.1'

local cjson = require('cjson.safe')
local log	= require("abtesting.utils.log")
--将doresp和dolog，与handler统一起来。
--handler将返回一个table，结构为：
--[[
handler———errinfo————errcode————code
    |           |               |
    |           |               |————info
    |           |
    |           |————errdesc
    |
    |
    |
    |———errstack				 
]]--		

_M.dolog = function(info, desc, data, errstack)
--    local errlog = 'ab_admin '
    local errlog = ''
    local code, err = info[1], info[2]
    local errcode = code
    local errinfo = desc and err..desc or err 
    
    errlog = errlog .. 'code : '..errcode
    errlog = errlog .. ', desc : '..errinfo
    if data then
        errlog = errlog .. ', extrainfo : '..data
    end
    if errstack then
        errlog = errlog .. ', errstack : '..errstack
    end
	return errlog
end

_M.doresp = function(info, desc, data)
    local response = {}
    
    local code = info[1]
    local err  = info[2]
    response.code = code
    response.desc = desc and err..desc or err 
    if data then 
        response.data = data 
    end
    
    return cjson.encode(response)
end

_M.doerror = function(info, extrainfo)
    local errinfo   = info[1]
    local errstack  = info[2] 
    local err, desc = errinfo[1], errinfo[2]

    local dolog, doresp = _M.dolog, _M.doresp
    local errlog = dolog(err, desc, extrainfo, errstack)
	log:errlog(errlog)

    local response  = doresp(err, desc)
    return response
end

_M.split = function (szFullString, szSeparator)
    local nFindStartIndex = 1
    local nSplitIndex = 1
    local nSplitArray = {}
    while true do
        local nFindLastIndex = string.find(szFullString, szSeparator, nFindStartIndex)
        if not nFindLastIndex then
            nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, string.len(szFullString))
            break
        end
        nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, nFindLastIndex - 1)
        nFindStartIndex = nFindLastIndex + string.len(szSeparator)
        nSplitIndex = nSplitIndex + 1
    end
    return nSplitArray
end

_M.split2 = function(input, delimiter)
    input = tostring(input)
    delimiter = tostring(delimiter)
    if (delimiter=='') then return false end

    local pos,arr = 0, {}

    -- for each divider found

    for st,sp in function() return string.find(input, delimiter, pos, true) end do

        table.insert(arr, string.sub(input, pos, st - 1))

        pos = sp + 1

    end

    table.insert(arr, string.sub(input, pos))

    return arr

end

return _M
