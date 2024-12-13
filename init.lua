local obj = {}
obj.__index = obj

-- Metadata
obj.name = "NetworkInfo"
obj.version = "2.2"
obj.author = "James Turnbull <james@lovedthanlost.net>"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/jamtur01/NetworkInfo.spoon"

-- Constants
local GEOIP_SERVICE_URL = "http://ip-api.com/json/"
local REFRESH_INTERVAL = 120 -- seconds
local SERVICE_CHECK_INTERVAL = 30 -- seconds
local EXPECTED_DNS = "127.0.0.1"
local TEST_DOMAINS = {"example.com", "google.com", "cloudflare.com"} -- Multiple domains for DNS testing

-- State variables
local serviceStates = {
    unbound = { pid = nil, running = false, responding = false },
    kresd = { pid = nil, running = false, responding = false }
}
local data = {
    geoIPData = nil,
    dnsInfo = nil,
    dnsTest = nil,
    localIP = nil,
    ssid = nil,
    vpnConnections = nil
}

-- Helper functions
local function copyToClipboard(_, payload)
    hs.pasteboard.writeObjects(payload.title:match(":%s*(.+)"))
end

local function updateMenu(menuItems)
    if obj.menu then
        obj.menu:setMenu(menuItems)
    end
end

local function addMenuItem(menuItems, item)
    table.insert(menuItems, item)
    updateMenu(menuItems)
end

-- Asynchronous data fetching functions
local function getGeoIPData()
    hs.http.asyncGet(GEOIP_SERVICE_URL, nil, function(status, response)
        if status == 200 then
            data.geoIPData = hs.json.decode(response)
        else
            data.geoIPData = { query = "N/A", isp = "N/A", country = "N/A", countryCode = "N/A" }
        end
        obj:buildMenu()
    end)
end

local function getLocalIPAddress()
    hs.task.new("/bin/sh", function(exitCode, stdOut, stdErr)
        data.localIP = stdOut:match("%d+%.%d+%.%d+%.%d+") or "N/A"
        obj:buildMenu()
    end, {"-c", "ipconfig getifaddr en0"}):start()
end

local function getCurrentSSID()
    local ssid = hs.wifi.currentNetwork("en0")
    data.ssid = ssid or "Not connected"
    obj:buildMenu()
end

local function getVPNConnections()
    hs.task.new("/bin/sh", function(exitCode, stdOut, stdErr)
        local vpnConnections = {}
        for line in stdOut:gmatch("[^\r\n]+") do
            local interface, ip = line:match("VPN Interface: (%S+), IP Address: (%S+)")
            if interface and ip then
                table.insert(vpnConnections, { name = interface, ip = ip })
            end
        end
        data.vpnConnections = vpnConnections
        obj:buildMenu()
    end, {"-c", [[
        for iface in $(ifconfig -l | grep -o 'utun[0-9]*'); do
            ip=$(ifconfig "$iface" | awk '/inet / {print $2}')
            if [ -n "$ip" ]; then
                echo "VPN Interface: $iface, IP Address: $ip"
            fi
        done
    ]]}):start()
end

local function getDNSInfo()
    hs.task.new("/bin/sh", function(exitCode, stdOut, stdErr)
        local dnsInfo = {}
        local uniqueDNS = {}
        for dns in stdOut:gmatch("%S+") do
            if not uniqueDNS[dns] then
                uniqueDNS[dns] = true
                table.insert(dnsInfo, dns)
            end
        end
        data.dnsInfo = dnsInfo
        obj:buildMenu()
    end, {"-c", "scutil --dns | grep 'nameserver\\[[0-9]*\\]' | awk '{print $3}'"}):start()
end

local function testDNSResolution()
    local results = {}
    local completed = 0
    for _, domain in ipairs(TEST_DOMAINS) do
        hs.task.new("/usr/bin/dig", function(exitCode, stdOut, stdErr)
            completed = completed + 1
            local success = stdOut:match("%d+%.%d+%.%d+%.%d+") ~= nil
            results[domain] = { success = success, response = stdOut }
            if completed == #TEST_DOMAINS then
                local successes = 0
                for _, result in pairs(results) do
                    if result.success then
                        successes = successes + 1
                    end
                end
                data.dnsTest = {
                    working = successes > 0,
                    successRate = successes / #TEST_DOMAINS * 100,
                    details = results
                }
                obj:buildMenu()
            end
        end, {"@127.0.0.1", domain, "+short", "+time=2"}):start()
    end
end

local function getServiceInfo(service, label)
    hs.task.new("/bin/launchctl", function(exitCode, stdOut, stdErr)
        local info = {}
        if stdOut:match("could not find service") then
            info.running = false
            info.pid = nil
        else
            info.running = stdOut:match("state = running") ~= nil
            info.pid = tonumber(stdOut:match("pid = (%d+)"))
        end
        serviceStates[service].running = info.running
        serviceStates[service].pid = info.pid
        obj:checkServiceResponse(service)
    end, {"print", "system/" .. label}):start()
end

function obj:checkServiceResponse(service)
    local server = "127.0.0.1"
    local port = service == "unbound" and "53" or "53153"
    hs.task.new("/usr/bin/dig", function(exitCode, stdOut, stdErr)
        local responding = stdOut:match("%d+%.%d+%.%d+%.%d+") ~= nil
        local prevState = serviceStates[service].responding
        serviceStates[service].responding = responding
        if prevState ~= responding then
            local status = string.format("%s: %s (PID: %s) - %s",
                service,
                serviceStates[service].running and "Running" or "Stopped",
                serviceStates[service].pid or "N/A",
                responding and "Responding" or "Not Responding"
            )
            hs.notify.new({
                title = "DNS Service Status Change",
                informativeText = status
            }):send()
        end
        obj:buildMenu()
    end, {"@" .. server, "-p", port, "example.com", "+short", "+time=2"}):start()
end

function obj:monitorServices()
    local services = {
        unbound = "org.cronokirby.unbound",
        kresd = "org.knot-resolver.kresd"
    }
    for service, label in pairs(services) do
        getServiceInfo(service, label)
    end
end

function obj:buildMenu()
    local menuItems = {}

    -- Public IP
    local publicIP = data.geoIPData and data.geoIPData.query or "N/A"
    addMenuItem(menuItems, { title = "🌍 Public IP: " .. publicIP, fn = copyToClipboard })

    -- Local IP
    local localIP = data.localIP or "N/A"
    addMenuItem(menuItems, { title = "💻 Local IP: " .. localIP, fn = copyToClipboard })

    -- SSID
    local ssid = data.ssid or "Not connected"
    addMenuItem(menuItems, { title = "📶 SSID: " .. ssid, fn = copyToClipboard })

    -- DNS Configuration
    if data.dnsInfo then
        addMenuItem(menuItems, { title = "-" })
        addMenuItem(menuItems, { title = "🔒 DNS Configuration:", disabled = true })
        for _, dns in ipairs(data.dnsInfo) do
            local icon = dns == EXPECTED_DNS and "✅" or "⚠️"
            addMenuItem(menuItems, { title = string.format("  %s %s", icon, dns), fn = copyToClipboard, indent = 1 })
        end
    end

    -- VPN Connections
    if data.vpnConnections and #data.vpnConnections > 0 then
        addMenuItem(menuItems, { title = "-" })
        addMenuItem(menuItems, { title = "🔐 VPN Connections:", disabled = true })
        for _, vpn in ipairs(data.vpnConnections) do
            addMenuItem(menuItems, { title = string.format("  • %s: %s", vpn.name, vpn.ip), fn = copyToClipboard, indent = 1 })
        end
    end

    -- Service Status
    addMenuItem(menuItems, { title = "-" })
    addMenuItem(menuItems, { title = "🔄 Service Status:", disabled = true })
    for service, state in pairs(serviceStates) do
        local runningStatus = state.running and "Running" or "Stopped"
        local pidInfo = state.pid and (" (PID: " .. state.pid .. ")") or " (PID: N/A)"

        local respondingInfo = ""
        if state.running then
            respondingInfo = state.responding and " - Responding" or " - Not Responding"
        end

        addMenuItem(menuItems, {
            title = string.format("  • %s: %s%s%s",
                service:gsub("^%l", string.upper),
                runningStatus,
                pidInfo,
                respondingInfo
            ),
            indent = 1
        })
    end

    -- DNS Resolution
    if data.dnsTest then
        addMenuItem(menuItems, {
            title = string.format("  • DNS Resolution: %.1f%% Success Rate", data.dnsTest.successRate),
            indent = 1
        })
    end

    -- ISP and Location
    local isp = data.geoIPData and data.geoIPData.isp or "N/A"
    local country = data.geoIPData and data.geoIPData.country or "N/A"
    local countryCode = data.geoIPData and data.geoIPData.countryCode or "N/A"
    addMenuItem(menuItems, { title = "-" })
    addMenuItem(menuItems, { title = "📇 ISP: " .. isp, fn = copyToClipboard })
    addMenuItem(menuItems, { title = "📍 Location: " .. country .. " (" .. countryCode .. ")", fn = copyToClipboard })

    -- Refresh Option
    addMenuItem(menuItems, { title = "-" })
    addMenuItem(menuItems, { title = "🔄 Refresh", fn = function() self:refreshData() end })

    -- Set Menu Title and Tooltip
    obj.menu:setTitle("🔗")
    obj.menu:setTooltip("NetworkInfo")
end

function obj:refreshData()
    data = {}
    getGeoIPData()
    getLocalIPAddress()
    getCurrentSSID()
    getVPNConnections()
    getDNSInfo()
    testDNSResolution()
    self:monitorServices()
end

function obj:start()
    self.menu = hs.menubar.new()
    self:refreshData()
    self.refreshTimer = hs.timer.doEvery(REFRESH_INTERVAL, function()
        self:refreshData()
    end)
    self.serviceTimer = hs.timer.doEvery(SERVICE_CHECK_INTERVAL, function()
        self:monitorServices()
    end)
    return self
end

function obj:stop()
    if self.refreshTimer then
        self.refreshTimer:stop()
        self.refreshTimer = nil
    end
    if self.serviceTimer then
        self.serviceTimer:stop()
        self.serviceTimer = nil
    end
    if self.menu then
        self.menu:delete()
        self.menu = nil
    end
    return self
end

return obj
