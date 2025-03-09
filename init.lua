local obj = {}
obj.__index = obj

-- Metadata
obj.name = "NetworkInfo"
obj.version = "2.4"
obj.author = "James Turnbull <james@lovedthanlost.net>"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/jamtur01/NetworkInfo.spoon"

-- Constants
local GEOIP_SERVICE_URL = "http://ip-api.com/json/"
local REFRESH_INTERVAL = 120 -- seconds
local SERVICE_CHECK_INTERVAL = 60 -- seconds
local EXPECTED_DNS = "127.0.0.1"
local TEST_DOMAINS = {"example.com", "google.com", "cloudflare.com"} -- Multiple domains for DNS testing
local DNS_CONFIG_PATH = os.getenv("HOME") .. "/.config/hammerspoon/dns.conf"
local TAILSCALE_INTERFACE = "utun" -- Base name for Tailscale interfaces

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
    vpnConnections = nil,
    dnsConfiguration = nil,
    tailscaleConnected = false
}

-- Cache for last applied DNS configuration
local lastAppliedDNSConfig = { ssid = nil, servers = nil }

-- Forward declarations
local updateMenu, addMenuItem, getCurrentSSID, checkTailscaleConnection

-- Helper functions
local function copyToClipboard(_, payload)
    hs.pasteboard.writeObjects(payload.title:match(":%s*(.+)"))
end

function updateMenu(menuItems)
    if obj.menu then
        obj.menu:setMenu(menuItems)
    end
end

function addMenuItem(menuItems, item)
    table.insert(menuItems, item)
    updateMenu(menuItems)
end

-- Tailscale detection function
function checkTailscaleConnection()
    hs.task.new("/bin/sh", function(exitCode, stdOut, stdErr)
        local previousState = data.tailscaleConnected
        data.tailscaleConnected = false
        
        for line in stdOut:gmatch("[^\r\n]+") do
            local interface = line:match("^%s*(%S+)")
            if interface and interface:match("^utun") then
                -- Check if the interface is actually Tailscale by looking for a specific Tailscale IP range
                hs.task.new("/bin/sh", function(exitCode, stdOut, stdErr)
                    if stdOut:match("100%.") then -- Tailscale IPs typically start with 100.*
                        data.tailscaleConnected = true
                        print("Tailscale detected on interface: " .. interface)
                        
                        -- If Tailscale state changed, reset DNS to default
                        if data.tailscaleConnected ~= previousState and data.tailscaleConnected then
                            print("Tailscale connected. Resetting DNS to default.")
                            resetDNSToDefault()
                        end
                        
                        obj:buildMenu()
                    end
                end, {"-c", "ifconfig " .. interface .. " | grep 'inet ' | awk '{print $2}'"}):start()
            end
        end
    end, {"-c", "ifconfig -l | tr ' ' '\\n' | grep '^utun'"}):start()
end

local function resetDNSToDefault()
    local cmd = "/usr/sbin/networksetup -setdnsservers Wi-Fi empty"
    local success = os.execute(cmd)
    
    if success then
        print("DNS reset to default successful")
        lastAppliedDNSConfig.ssid = nil
        lastAppliedDNSConfig.servers = nil
        
        hs.notify.new({
            title = "DNS Settings Reset",
            informativeText = "Tailscale detected. DNS settings reset to default."
        }):send()
        
        return true
    else
        print("Failed to reset DNS to default")
        return false
    end
end

-- DNS Configuration functions
local function readDNSConfig(ssid)
    if not ssid then return nil, false end

    local f = io.open(DNS_CONFIG_PATH, "r")
    if not f then
        print("DNS config file not found at " .. DNS_CONFIG_PATH)
        return nil, false
    end

    for line in f:lines() do
        if line:match("^%s*$") or line:match("^%s*#") then
            goto continue
        end

        local configSSID, dnsServers = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
        if configSSID and dnsServers and configSSID == ssid then
            f:close()
            return dnsServers, true
        end

        ::continue::
    end

    f:close()
    return nil, false
end

local function updateDNSSettings(dnsServers)
    if not dnsServers then return false end
    
    -- If Tailscale is connected, don't update DNS and use default instead
    if data.tailscaleConnected then
        print("Tailscale is connected. Using default DNS instead of custom configuration.")
        return resetDNSToDefault()
    end

    local dnsArray = {}
    for server in dnsServers:gmatch("%S+") do
        table.insert(dnsArray, server)
    end

    local cmd = string.format("/usr/sbin/networksetup -setdnsservers Wi-Fi %s", table.concat(dnsArray, " "))
    local success = os.execute(cmd)

    if success then
        print("DNS update successful: " .. dnsServers)
        return true
    else
        print("Failed to update DNS")
        return false
    end
end

-- Async data fetching functions
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

function getCurrentSSID()
    local ssid = hs.wifi.currentNetwork()
    data.ssid = ssid or "Not connected"

    -- First check if Tailscale is connected
    checkTailscaleConnection()
    
    if ssid then
        local dnsServers, configured = readDNSConfig(ssid)
        if configured then
            data.dnsConfiguration = {
                ssid = ssid,
                servers = dnsServers,
                configured = true
            }
            
            -- Only update DNS settings if Tailscale is not connected and SSID or DNS servers have changed
            if not data.tailscaleConnected and (lastAppliedDNSConfig.ssid ~= ssid or lastAppliedDNSConfig.servers ~= dnsServers) then
                if updateDNSSettings(dnsServers) then
                    hs.notify.new({
                        title = "Wi-Fi DNS Changed",
                        informativeText = string.format("Connected to %s with DNS: %s", ssid, dnsServers)
                    }):send()
                    lastAppliedDNSConfig.ssid = ssid
                    lastAppliedDNSConfig.servers = dnsServers
                end
            end
        else
            data.dnsConfiguration = {
                ssid = ssid,
                configured = false
            }
            if not data.tailscaleConnected then
                lastAppliedDNSConfig.ssid = nil
                lastAppliedDNSConfig.servers = nil
            }
        end
    else
        data.dnsConfiguration = nil
        if not data.tailscaleConnected then
            lastAppliedDNSConfig.ssid = nil
            lastAppliedDNSConfig.servers = nil
        }
    end

    obj:buildMenu()
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

-- File watcher for dns.conf changes
function obj:watchConfigFile()
    if self.configWatcher then
        self.configWatcher:stop()
    end
    self.configWatcher = hs.pathwatcher.new(DNS_CONFIG_PATH, function(files)
        print("dns.conf has changed. Reloading DNS configuration.")
        -- Force a re-read of the configuration.
        getCurrentSSID()
    end)
    self.configWatcher:start()
end

-- Menu building
function obj:buildMenu()
    local menuItems = {}

    -- Public IP
    local publicIP = data.geoIPData and data.geoIPData.query or "N/A"
    addMenuItem(menuItems, { title = "🌍 Public IP: " .. publicIP, fn = copyToClipboard })

    -- Local IP
    local localIP = data.localIP or "N/A"
    addMenuItem(menuItems, { title = "💻 Local IP: " .. localIP, fn = copyToClipboard })

    -- SSID with DNS Configuration
    local ssid = data.ssid or "Not connected"
    addMenuItem(menuItems, { title = "📶 SSID: " .. ssid, fn = copyToClipboard })

    -- Tailscale Status
    local tailscaleStatus = data.tailscaleConnected and "Connected" or "Disconnected"
    local tailscaleIcon = data.tailscaleConnected and "✅" or "❌"
    addMenuItem(menuItems, { title = "🔒 Tailscale: " .. tailscaleIcon .. " " .. tailscaleStatus })

    if data.dnsConfiguration then
        if data.tailscaleConnected then
            addMenuItem(menuItems, {
                title = "  ℹ️ Using Default DNS (Tailscale Connected)",
                disabled = true,
                indent = 1
            })
        } else if data.dnsConfiguration.configured then
            addMenuItem(menuItems, {
                title = string.format("  ✅ DNS Config: %s", data.dnsConfiguration.servers),
                fn = copyToClipboard,
                indent = 1
            })
        } else {
            addMenuItem(menuItems, {
                title = "  ⚠️ No Custom DNS Config",
                disabled = true,
                indent = 1
            })
        }
    end

    -- DNS Information
    if data.dnsInfo then
        addMenuItem(menuItems, { title = "-" })
        addMenuItem(menuItems, { title = "🔒 DNS Configuration:", disabled = true })
        local expectedDNS = {}
        if data.tailscaleConnected then
            -- When Tailscale is connected, we're using default DNS so we don't have expected values
            addMenuItem(menuItems, { title = "  ℹ️ Using Default DNS (System Provided)", disabled = true, indent = 1 })
        } else if data.dnsConfiguration and data.dnsConfiguration.configured then
            for server in data.dnsConfiguration.servers:gmatch("%S+") do
                expectedDNS[server] = true
            end
        } else {
            expectedDNS[EXPECTED_DNS] = true
        }
        
        for _, dns in ipairs(data.dnsInfo) do
            local icon = expectedDNS[dns] and "✅" or "⚠️"
            if data.tailscaleConnected then
                icon = "ℹ️"  -- When Tailscale connected, all DNS entries are informational
            end
            addMenuItem(menuItems, { title = string.format("  %s %s", icon, dns), fn = copyToClipboard, indent = 1 })
        end
    end

    -- VPN Connections
    if data.vpnConnections and #data.vpnConnections > 0 then
        addMenuItem(menuItems, { title = "-" })
        addMenuItem(menuItems, { title = "🔐 VPN Connections:", disabled = true })
        for _, vpn in ipairs(data.vpnConnections) do
            local isTailscale = vpn.name:match("^utun") and "Tailscale: " or ""
            addMenuItem(menuItems, { title = string.format("  • %s%s: %s", isTailscale, vpn.name, vpn.ip), fn = copyToClipboard, indent = 1 })
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
    if data.geoIPData then
        local isp = data.geoIPData.isp or "N/A"
        local country = data.geoIPData.country or "N/A"
        local countryCode = data.geoIPData.countryCode or "N/A"
        addMenuItem(menuItems, { title = "-" })
        addMenuItem(menuItems, { title = "📇 ISP: " .. isp, fn = copyToClipboard })
        addMenuItem(menuItems, { title = "📍 Location: " .. country .. " (" .. countryCode .. ")", fn = copyToClipboard })
    end

    -- Refresh Option
    addMenuItem(menuItems, { title = "-" })
    addMenuItem(menuItems, { title = "🔄 Refresh", fn = function() self:refreshData() end })

    -- Set Menu Title and Tooltip
    obj.menu:setTitle("🔗")
    obj.menu:setTooltip("NetworkInfo")
end

function obj:refreshData()
    data = {
        dnsConfiguration = data.dnsConfiguration,  -- Preserve DNS configuration
        tailscaleConnected = data.tailscaleConnected  -- Preserve Tailscale status
    }
    checkTailscaleConnection()
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

    -- Set up WiFi watcher
    self.wifiWatcher = hs.wifi.watcher.new(function()
        print("Network configuration changed")
        getCurrentSSID()
    end)
    self.wifiWatcher:start()

    -- Set up file watcher for dns.conf
    self:watchConfigFile()

    -- Regular refresh timer
    self.refreshTimer = hs.timer.doEvery(REFRESH_INTERVAL, function()
        self:refreshData()
    end)

    -- Service monitoring timer
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
    if self.wifiWatcher then
        self.wifiWatcher:stop()
        self.wifiWatcher = nil
    end
    if self.configWatcher then
        self.configWatcher:stop()
        self.configWatcher = nil
    end
    if self.menu then
        self.menu:delete()
        self.menu = nil
    end
    return self
end

return obj