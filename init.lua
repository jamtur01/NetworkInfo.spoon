--- === NetworkInfo ===
---
--- A drop-down menu listing your public IP information, current DNS servers, Wi-Fi SSID, and VPN details.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "NetworkInfo"
obj.version = "1.7"
obj.author = "James Turnbull <james@lovedthanlost.net>"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/jamtur01/NetworkInfo.spoon"

-- Constants
local GEOIP_SERVICE_URL = "http://ip-api.com/json/"
local REFRESH_INTERVAL = 120 -- seconds
local RETRY_DELAY = 30 -- seconds

-- State variables
local previousState = {}
local isFirstRun = true

-- Helper functions
local function copyToClipboard(_, payload)
    hs.pasteboard.writeObjects(payload.title:match(":%s*(.+)"))
end

local function getGeoIPData()
    local status, data = hs.http.get(GEOIP_SERVICE_URL)
    if status == 200 and data then
        local decodedJSON = hs.json.decode(data)
        if decodedJSON then
            return decodedJSON
        end
    end
    return {
        err = status == 0 and "No internet connection or DNS issue" or
              status == 429 and "Rate limited. Retrying..." or
              "Failed to fetch data. HTTP status: " .. tostring(status),
        errMsg = status == 429 and "Throttled. Retrying..." or "N/A",
        httpStatus = status,
        rawData = data or ""
    }
end

local function getLocalIPAddress()
    local details = hs.network.interfaceDetails("en0")
    return details and details.IPv4 and details.IPv4.Addresses and details.IPv4.Addresses[1] or "N/A"
end

local function getDNSInfo()
    local dnsInfo = {}
    local uniqueDNS = {}

    local function addDNS(dns)
        if not uniqueDNS[dns] then
            table.insert(dnsInfo, dns)
            uniqueDNS[dns] = true
        end
    end

    -- Manual DNS
    local manualDNS = hs.execute("networksetup -getdnsservers Wi-Fi"):gsub("\n", "")
    if manualDNS:find("There aren't any DNS Servers set") then
        table.insert(dnsInfo, "No manually configured DNS")
    else
        for dns in manualDNS:gmatch("%S+") do
            addDNS(dns)
        end
    end

    -- DHCP/Automatic DNS
    for dns in hs.execute("scutil --dns"):gmatch("nameserver%[%d+%] : (%S+)") do
        addDNS(dns)
    end

    return dnsInfo
end

local function getCurrentSSID()
    return hs.wifi.currentNetwork() or "Not connected"
end

local function getVPNConnections()
    local vpnConnections = {}
    for _, interface in ipairs(hs.network.interfaces()) do
        if interface:match("^utun%d+$") then
            local details = hs.network.interfaceDetails(interface)
            if details and details.IPv4 and details.IPv4.Addresses then
                table.insert(vpnConnections, {name = interface, ip = details.IPv4.Addresses[1]})
            end
        end
    end
    return vpnConnections
end

-- Main functions
function obj:refreshIP()
    local geoIPData = getGeoIPData()
    local localIP = getLocalIPAddress()
    local dnsInfo = getDNSInfo()
    local ssid = getCurrentSSID()
    local vpnConnections = getVPNConnections()

    local currentState = {
        ssid = ssid,
        publicIP = geoIPData.query,
        localIP = localIP,
        dnsInfo = table.concat(dnsInfo, ", "),
        ISP = geoIPData.isp,
        country = geoIPData.country
    }

    if not isFirstRun then
        for key, value in pairs(currentState) do
            if previousState[key] ~= value then
                hs.notify.new({
                    title = "NetworkInfo Update",
                    informativeText = string.format("%s changed to: %s", key, value)
                }):send()
            end
        end
    else
        isFirstRun = false
    end

    previousState = currentState

    local menuItems = {}

    if not geoIPData.err then
        table.insert(menuItems, {title = "🌍 Public IP: " .. geoIPData.query, fn = copyToClipboard})
        table.insert(menuItems, {title = "💻 Local IP: " .. localIP, fn = copyToClipboard})
        table.insert(menuItems, {title = "📶 SSID: " .. ssid, fn = copyToClipboard})
        table.insert(menuItems, {title = "🔒 DNS Servers:", disabled = true})
        for _, dns in ipairs(dnsInfo) do
            table.insert(menuItems, {title = "  • " .. dns, fn = copyToClipboard, indent = 1})
        end
        if #vpnConnections > 0 then
            table.insert(menuItems, {title = "🔐 VPN Connections:", disabled = true})
            for _, vpn in ipairs(vpnConnections) do
                table.insert(menuItems, {title = string.format("  • %s: %s", vpn.name, vpn.ip), fn = copyToClipboard, indent = 1})
            end
        end
        table.insert(menuItems, {title = "-"})
        table.insert(menuItems, {title = "📇 ISP: " .. geoIPData.isp, fn = copyToClipboard})
        table.insert(menuItems, {title = "📍 Location: " .. geoIPData.country .. " (" .. geoIPData.countryCode .. ")", fn = copyToClipboard})
    else
        table.insert(menuItems, {title = "⚠️ " .. geoIPData.errMsg, fn = copyToClipboard, disabled = false})
        table.insert(menuItems, {title = "Check logs for more details.", disabled = true})
        if geoIPData.httpStatus == 429 then
            hs.timer.doAfter(RETRY_DELAY, function() self:refreshIP() end)
        end
    end

    table.insert(menuItems, {title = "-"})
    table.insert(menuItems, {title = "🔄 Refresh", fn = function() self:refreshIP() end})

    self.menu:setTitle("🔗")
    self.menu:setMenu(menuItems)
end

function obj:start()
    self.menu = hs.menubar.new()
    isFirstRun = true
    self:refreshIP()
    self.timer = hs.timer.doEvery(REFRESH_INTERVAL, function() self:refreshIP() end)
    return self
end

function obj:stop()
    if self.timer then
        self.timer:stop()
        self.timer = nil
    end
    if self.menu then
        self.menu:delete()
        self.menu = nil
    end
    return self
end

return obj