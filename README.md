# NetworkInfo Spoon

## Overview

The `NetworkInfo` Spoon is a Hammerspoon utility that provides comprehensive network monitoring and DNS management capabilities through the macOS menu bar. It displays essential network information, monitors DNS services, manages per-network DNS configurations, and provides real-time status updates for network changes.

## Features

- **Network Information Display:**

  - Public IP address with geolocation data
  - Local IP address for primary network interface
  - Current WiFi SSID
  - ISP information
  - Country and location data
  - Active VPN connections detection

- **DNS Management:**

  - Per-network DNS configuration support
  - Automatic DNS server switching based on WiFi network
  - DNS service monitoring (Unbound and Knot Resolver)
  - DNS resolution testing with multiple domains
  - Configuration through `~/.config/hammerspoon/dns.conf`

- **Real-time Monitoring:**

  - Automatic refresh every 120 seconds
  - Service status monitoring every 30 seconds
  - WiFi network change detection
  - DNS configuration file watching
  - Service health notifications

- **User Interface:**
  - Clean, hierarchical menu organization
  - Copy-to-clipboard functionality for most values
  - Status indicators for DNS configuration and services
  - Manual refresh option

## Installation

1. **Download the Spoon:**

   - Download the `NetworkInfo.spoon` folder
   - Place it in your Hammerspoon Spoons directory (`~/.hammerspoon/Spoons/`)

2. **Create DNS Configuration:**

   - Create the file `~/.config/hammerspoon/dns.conf`
   - Add DNS configurations (see Configuration section)

3. **Load the Spoon:**
   Add to your Hammerspoon configuration (`init.lua`):
   ```lua
   hs.loadSpoon("NetworkInfo")
   spoon.NetworkInfo:start()
   ```

## Configuration

### DNS Configuration File

Create a DNS configuration file at `~/.config/hammerspoon/dns.conf` with the following format:

```text
# Format: SSID = DNS_SERVER1 DNS_SERVER2 ...
HomeNetwork = 1.1.1.1 1.0.0.1
WorkWifi = 10.0.0.53 8.8.8.8
```

Each line specifies:

- The WiFi SSID
- An equals sign (=)
- One or more DNS servers, separated by spaces

Comments (lines starting with #) and empty lines are ignored.

### Menu Bar Display

The menu bar shows a chain link icon (🔗) with a tooltip "NetworkInfo". Clicking reveals:

- Public IP address with copy option
- Local IP address with copy option
- Current SSID with DNS configuration status
- DNS server list with validation indicators
- VPN connection details (when active)
- Service status for DNS resolvers
- DNS resolution test results
- ISP and location information
- Manual refresh option

### Service Monitoring

The spoon monitors:

- Unbound DNS resolver (org.cronokirby.unbound)
- Knot Resolver (org.knot-resolver.kresd)

For each service, it tracks:

- Running status
- Process ID
- Response status
- Notifications for status changes

## Advanced Features

### DNS Resolution Testing

The spoon tests DNS resolution using multiple domains:

- example.com
- google.com
- cloudflare.com

Results show:

- Success rate percentage
- Individual test outcomes
- Response details

### VPN Detection

Automatically detects and displays:

- Active VPN interfaces (utun\*)
- VPN IP addresses
- Connection status

### Automatic DNS Management

When connecting to a configured WiFi network:

- Reads DNS configuration from dns.conf
- Automatically applies DNS settings
- Sends notification of changes
- Maintains configuration across network switches

## Troubleshooting

1. **DNS Configuration Issues:**

   - Verify dns.conf format and permissions
   - Check system DNS settings: `scutil --dns`
   - Monitor console for configuration changes

2. **Service Monitoring:**

   - Check service status: `launchctl print system/org.cronokirby.unbound`
   - Verify service response: `dig @127.0.0.1 example.com`

3. **General Issues:**
   - Review Hammerspoon console for errors
   - Verify file permissions
   - Check network interface status

## Version History

Current Version: 2.3

- Added per-network DNS configuration
- Implemented service monitoring
- Added VPN detection
- Enhanced DNS resolution testing
- Added configuration file watching

## License

This Spoon is licensed under the MIT License. See the [LICENSE](https://opensource.org/licenses/MIT) file for details.

## Author

James Turnbull <james@lovedthanlost.net>  
https://github.com/jamtur01/NetworkInfo.spoon

## Credits

- Original DNS module inspiration from [senorprogrammer](https://github.com/senorprogrammer/hammerspoon_init/blob/master/lib/dns.lua)
- Based on concepts from Sibin Arsenijević's PublicIP Spoon
