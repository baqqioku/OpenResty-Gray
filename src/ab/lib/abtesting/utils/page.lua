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


_M.page = function(self)
    local page = {}
    page.currentPage = self.currentPage
    page.pageSize = self.pageSize
    page.total = self.total
    page.body = self.body
    return page
end







return _M