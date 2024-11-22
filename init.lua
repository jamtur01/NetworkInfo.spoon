--- === NetworkInfo ===
---
--- A drop-down menu listing your public IP information, current DNS servers, Wi-Fi SSID, and VPN details.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "NetworkInfo"
obj.version = "2.0"
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

local function getGeoIPData(callback)
    hs.http.asyncGet(GEOIP_SERVICE_URL, nil, function(status, data)
        local result
        if status == 200 and data then
            local decodedJSON = hs.json.decode(data)
            if decodedJSON then
                result = decodedJSON
            end
        else
            result = {
                err = status == 0 and "No internet connection or DNS issue" or
                      status == 429 and "Rate limited. Retrying..." or
                      "Failed to fetch data. HTTP status: " .. tostring(status),
                errMsg = status == 429 and "Throttled. Retrying..." or "N/A",
                httpStatus = status,
                rawData = data or ""
            }
        end
        callback(result)
    end)
end

local function getLocalIPAddress()
    local details = hs.network.interfaceDetails("en0")
    return details and details.IPv4 and details.IPv4.Addresses and details.IPv4.Addresses[1] or "N/A"
end

local function getDNSInfo()
    local dnsInfo = {}
    local uniqueDNS = {}

    local function addDNS(dns)
        if dns and not uniqueDNS[dns] then
            table.insert(dnsInfo, dns)
            uniqueDNS[dns] = true
        end
    end

    -- Manual DNS
    local manualDNS = hs.execute("networksetup -getdnsservers Wi-Fi"):gsub("\n", "")
    if manualDNS and not manualDNS:find("There aren't any DNS Servers set") then
        for dns in manualDNS:gmatch("%S+") do
            addDNS(dns)
        end
    else
        table.insert(dnsInfo, "No manually configured DNS")
    end

    -- DHCP/Automatic DNS
    local scutilOutput = hs.execute("scutil --dns")
    if scutilOutput then
        for dns in scutilOutput:gmatch("nameserver%[%d+%] : (%S+)") do
            addDNS(dns)
        end
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

-- New: Check if Unbound and Kresd services are running
local function checkService(label)
    local output = hs.execute("launchctl list | grep -q '" .. label .. "' && echo 'running' || echo 'stopped'")
    return output:match("running") and true or false
end

-- New: Test DNS resolution
local function testDNSResolution()
    local result = hs.execute("dig @127.0.0.1 example.com +short")
    return result ~= nil and result:match("%d+%.%d+%.%d+%.%d+")
end

-- Main functions
function obj:refreshIP()
    getGeoIPData(function(geoIPData)
        if not geoIPData or geoIPData.err then
            local errMsg = geoIPData and geoIPData.err or "Failed to fetch GeoIP data."
            hs.notify.new({title = "NetworkInfo Error", informativeText = errMsg}):send()
            return
        end

        local localIP = getLocalIPAddress()
        local dnsInfo = getDNSInfo()
        local ssid = getCurrentSSID()
        local vpnConnections = getVPNConnections()

        -- Check Unbound and Kresd services
        local unboundRunning = checkService("org.cronokirby.unbound")
        local kresdRunning = checkService("org.knot-resolver.kresd")
        local dnsResolutionWorking = testDNSResolution()

        local currentState = {
            ssid = ssid,
            publicIP = geoIPData.query,
            localIP = localIP,
            dnsInfo = dnsInfo and table.concat(dnsInfo, ", ") or "N/A",
            ISP = geoIPData.isp,
            country = geoIPData.country,
            unboundStatus = unboundRunning and "Running" or "Stopped",
            kresdStatus = kresdRunning and "Running" or "Stopped",
            dnsResolution = dnsResolutionWorking and "Working" or "Failed"
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

        table.insert(menuItems, {title = "🌍 Public IP: " .. (geoIPData.query or "N/A"), fn = copyToClipboard})
        table.insert(menuItems, {title = "💻 Local IP: " .. (localIP or "N/A"), fn = copyToClipboard})
        table.insert(menuItems, {title = "📶 SSID: " .. (ssid or "N/A"), fn = copyToClipboard})
        table.insert(menuItems, {title = "🔒 DNS Servers:", disabled = true})
        for _, dns in ipairs(dnsInfo or {}) do
            table.insert(menuItems, {title = "  • " .. dns, fn = copyToClipboard, indent = 1})
        end
        if #vpnConnections > 0 then
            table.insert(menuItems, {title = "🔐 VPN Connections:", disabled = true})
            for _, vpn in ipairs(vpnConnections) do
                table.insert(menuItems, {title = string.format("  • %s: %s", vpn.name, vpn.ip), fn = copyToClipboard, indent = 1})
            end
        end
        table.insert(menuItems, {title = "-"})
        table.insert(menuItems, {title = "🔄 Service Status:", disabled = true})
        table.insert(menuItems, {title = "  • Unbound: " .. currentState.unboundStatus, indent = 1})
        table.insert(menuItems, {title = "  • Kresd: " .. currentState.kresdStatus, indent = 1})
        table.insert(menuItems, {title = "  • DNS Resolution: " .. currentState.dnsResolution, indent = 1})
        table.insert(menuItems, {title = "-"})
        table.insert(menuItems, {title = "📇 ISP: " .. (geoIPData.isp or "N/A"), fn = copyToClipboard})
        table.insert(menuItems, {title = "📍 Location: " .. (geoIPData.country or "N/A") .. " (" .. (geoIPData.countryCode or "N/A") .. ")", fn = copyToClipboard})

        table.insert(menuItems, {title = "-"})
        table.insert(menuItems, {title = "🔄 Refresh", fn = function() self:refreshIP() end})

        self.menu:setTitle("🔗")
        self.menu:setTooltip("NetworkInfo")
        self.menu:setMenu(menuItems)
    end)
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
