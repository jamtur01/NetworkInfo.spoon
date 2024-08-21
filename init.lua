--- === NetworkInfo ===
---
--- A drop-down menu listing your public IP information, current DNS servers, Wi-Fi SSID, and VPN details.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "NetworkInfo"
obj.version = "1.5"
obj.author = "James Turnbull <james@lovedthanlost.net>"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/jamtur01/NetworkInfo.spoon"

-- PublicIP Metadata and Variables
obj.publicIPGeolocationService = "http://ip-api.com/json/"
obj.terse = true

-- Previous state to detect changes
local previousState = {}
local isFirstRun = true

--- Callback function for menu items to call refreshIP method
function callRefresh(modifiers, payload)
    obj:refreshIP()
end

function copyToClipboard(modifiers, payload)
    hs.pasteboard.writeObjects(payload.title)
end

function getGeoIPData()
    local status, data, headers = hs.http.get(obj.publicIPGeolocationService)
    local decodedJSON = {}

    if status == 200 and data then
        decodedJSON = hs.json.decode(data)

        if not decodedJSON then
            decodedJSON = {}
            decodedJSON['err'] = "Failed to deserialize JSON from ip-api.com, service returned: " .. tostring(data)
            decodedJSON['errMsg'] = "N/A"
        else
            decodedJSON['err'] = nil
            decodedJSON['errMsg'] = nil
        end

    elseif status == 0 then
        decodedJSON['err'] = "GeoIP service is not resolvable. Either there is no internet connection, DNS servers are not responding, or GeoIP provider's DNS does not exist."
        decodedJSON['errMsg'] = "No Internet"

    elseif status == 429 then
        decodedJSON['err'] = "GeoIP requests are throttled, we are over 45 requests per minute from our IP. We will retry after 30 seconds. Consider subscribing to https://members.ip-api.com to support providers of geoip service."
        decodedJSON['errMsg'] = "Throttled. Retrying..."
        
        hs.timer.doAfter(30, function()
            obj:refreshIP()
        end)
    else
        decodedJSON['err'] = "Failed to fetch data. HTTP status: " .. tostring(status)
        decodedJSON['errMsg'] = "N/A"
    end

    decodedJSON['httpStatus'] = status
    decodedJSON['rawData'] = data or ""

    return decodedJSON
end

function getLocalIPAddress()
    local details = hs.network.interfaceDetails("en0")
    if details and details.IPv4 and details.IPv4.Addresses then
        return details.IPv4.Addresses[1]  -- Return the first IPv4 address found
    end
    return "N/A"
end

function getDNSInfo()
    local dnsInfo = {}
    local uniqueDNS = {}

    -- Get manually configured DNS servers
    local handle = io.popen("networksetup -getdnsservers Wi-Fi")
    local servers = handle:read("*a")
    handle:close()

    if servers:find("There aren't any DNS Servers set") then
        table.insert(dnsInfo, "No manually configured DNS")
    else
        for dns in string.gmatch(servers, "%S+") do
            if not uniqueDNS[dns] then
                table.insert(dnsInfo, dns)
                uniqueDNS[dns] = true
            end
        end
    end

    -- Get DHCP/Automatic DNS servers
    handle = io.popen("scutil --dns | grep 'nameserver\\[[0-9]*\\]'")
    local dhcp_servers = handle:read("*a")
    handle:close()

    for dns in string.gmatch(dhcp_servers, "nameserver%[%d+%] : (%S+)") do
        if not uniqueDNS[dns] then
            table.insert(dnsInfo, dns)
            uniqueDNS[dns] = true
        end
    end

    return dnsInfo
end

function getCurrentSSID()
    local ssid = hs.execute("networksetup -getairportnetwork en0 | awk -F ': ' '{print $2}'")
    if ssid and ssid ~= "" then
        return ssid:gsub("\n", "")
    else
        return "Not connected"
    end
end

function getVPNConnections()
    local vpnConnections = {}

    -- Use ifconfig to get network interfaces
    local handle = io.popen("ifconfig")
    local ifconfig_output = handle:read("*a")
    handle:close()

    -- Look for interfaces containing "utun" (typical for VPN connections)
    for interface in ifconfig_output:gmatch("(%w*utun%d+)") do
        local details = hs.network.interfaceDetails(interface)
        if details and details.IPv4 and details.IPv4.Addresses then
            local ipAddress = details.IPv4.Addresses[1]
            table.insert(vpnConnections, {name = interface, ip = ipAddress})
        end
    end

    return vpnConnections
end

--- PublicIP:refreshIP()
--- Method
--- Refreshes IP information and redraws menubar widget
function obj:refreshIP()
    local geoIPData = getGeoIPData()
    local localIP = getLocalIPAddress()
    local dnsInfo = getDNSInfo()
    local ssid = getCurrentSSID()
    local vpnConnections = getVPNConnections()

    local ISP = geoIPData.isp
    local country = geoIPData.country
    local publicIP = geoIPData.query  
    local countryCode = geoIPData.countryCode
  
    local fetchError = geoIPData.err

    -- Check for changes and notify
    local currentState = {
        ssid = ssid,
        publicIP = publicIP,
        localIP = localIP,
        dnsInfo = table.concat(dnsInfo, ", "),
        ISP = ISP,
        country = country
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

    local menuTitle = "🔗"  -- Set the menu title to the network icon
    local menuItems = {}

    if fetchError == nil then
        -- Add each network item to the menu in a vertical list
        table.insert(menuItems, {title = "🌍 Public IP: " .. publicIP, fn = copyToClipboard})
        table.insert(menuItems, {title = "💻 Local IP (en0): " .. localIP, fn = copyToClipboard})
        table.insert(menuItems, {title = "📶 SSID: " .. ssid, fn = copyToClipboard})
        for _, dns in ipairs(dnsInfo) do
            table.insert(menuItems, {title = "DNS: " .. dns, fn = copyToClipboard})
        end
        -- Add VPN connections to the menu
        if #vpnConnections > 0 then
            table.insert(menuItems, {title = "VPN Connections:", disabled = true})
            for _, vpn in ipairs(vpnConnections) do
                table.insert(menuItems, {title = vpn.name .. ": " .. vpn.ip, fn = copyToClipboard})
            end
        end
        table.insert(menuItems, {title = "📇 ISP: " .. ISP, fn = copyToClipboard})
        table.insert(menuItems, {title = "📍 Country: " .. country .. ", " .. countryCode, fn = copyToClipboard})

        -- Add refresh option
        table.insert(menuItems, {title = "Refresh", fn = callRefresh})
    else
        menuItems = {
            {title = geoIPData.errMsg, fn = copyToClipboard, disabled = false},
            {title = "Check logs for more details.", disabled = true},
            {title = "Refresh", fn = callRefresh}
        }
    end

    self.menu:setTitle(menuTitle)
    self.menu:setMenu(menuItems)
end

--- NetworkInfo:start()
function obj:start()
    -- Initialize menu
    self.menu = hs.menubar.new()
    isFirstRun = true  -- Reset isFirstRun flag
    self:refreshIP()

    -- Refresh the menu every 120 seconds
    self.timer = hs.timer.doEvery(120, function() self:refreshIP() end)

    return self
end

--- NetworkInfo:stop()
function obj:stop()
    -- Stop the menu and timer
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