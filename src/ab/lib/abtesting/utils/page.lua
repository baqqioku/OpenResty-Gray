local modulename = "abtestingPage"

local _M = {}
local mt = {__index = _M}
_M._VERSION = "0.01"


_M.new = function(self,currentPage,pageSize,total,body)
    self.currentPage = currentPage
    self.pageSize = pageSize
    self.total = total
    self.body = body
    return setmetatable(self, { __index = _M } )
end







return _M