
local _M = {
    _VERSION = '0.01'
}

local ffi = require("ffi")

ffi.cdef[[
struct in_addr {
    uint32_t s_addr;
};

int inet_aton(const char *cp, struct in_addr *inp);
uint32_t ntohl(uint32_t netlong);

char *inet_ntoa(struct in_addr in);
uint32_t htonl(uint32_t hostlong);
]]

local C = ffi.C

function _M.ip2long(ip)
    local inp = ffi.new("struct in_addr[1]")
    if C.inet_aton(ip, inp) ~= 0 then
        return tonumber(C.ntohl(inp[0].s_addr))
    end
    return nil
end

function _M.long2ip(long)
    if type(long) ~= "number" then
        return nil
    end
    local addr = ffi.new("struct in_addr")
    addr.s_addr = C.htonl(long)
    return ffi.string(C.inet_ntoa(addr))
end



_M.get = function()
    local ClientIP = ngx.req.get_headers()["X-Real-IP"]
    if ClientIP == nil or string.len(ClientIP) == 0 or ClientIP == "unknown" then
--[[        ClientIP = ngx.req.get_headers()["X-Forwarded-For"]
        if ClientIP then
            local colonPos = string.find(ClientIP, ' ')
            local proxy_ip_list = ngx.var.proxy_add_x_forwarded_for
            if colonPos then
                ClientIP = string.sub(ClientIP, 1, colonPos - 1) 
            end
        end]]
        local proxy_ip_list = ngx.var.proxy_add_x_forwarded_for

        if proxy_ip_list then
            local clientipEnd = string.find(proxy_ip_list, ',', 1)
            if clientipEnd then
                ClientIP = string.sub(proxy_ip_list, 0, clientipEnd - 1)
            end
        end
    end
    if ClientIP == nil or string.len(ClientIP) == 0 or ClientIP == "unknown" then
        ClientIP = ngx.var.remote_addr
    end
    ngx.log(ngx.DEBUG,'ClientIP:',ClientIP)
    if ClientIP then 
        ClientIP = _M.ip2long(ClientIP)
    end
    return ClientIP
end

_M.get_ip2long = function()
    local ClientIP = _M.get()
    if ClientIP then
        ClientIP = _M.ip2long(ClientIP)
    end
    return ClientIP
end


return _M


