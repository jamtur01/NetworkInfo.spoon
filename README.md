# NetworkInfo Spoon

## Overview

The `NetworkInfo` Spoon is a Hammerspoon utility that displays essential network information in the macOS menu bar. This includes the current public IP, local IP, ISP, country information, and DNS servers (both manually configured and DHCP/automatic). The information is displayed in a clean, vertical list, and the menu automatically refreshes every 60 seconds.

## Features

- **Public IP Address:** Displays the public IP address of your current network.
- **Local IP Address:** Shows the local IP address associated with the primary network interface (usually `en0` for Wi-Fi).
- **ISP Information:** Lists the ISP providing your Internet connection.
- **Country Information:** Shows the country and country code based on the public IP.
- **DNS Servers:** Lists both manually configured and DHCP/automatic DNS servers, with duplicate entries filtered out.
- **Automatic Refresh:** The menu automatically refreshes every 60 seconds to ensure up-to-date information.

## Installation

1. **Download the Spoon:**

   - Download the `NetworkInfo.spoon` folder and place it in your Hammerspoon Spoons directory (`~/.hammerspoon/Spoons/`).

2. **Load the Spoon in your Hammerspoon configuration (`init.lua`):**

   ```lua
   hs.loadSpoon("NetworkInfo")
   ```

3. **Start the Spoon:**
   - Add the following line to your Hammerspoon configuration to start the Spoon:
   ```lua
   spoon.NetworkInfo:start()
   ```

## Usage

Once the Spoon is started, you will see a menu bar item that displays the country code associated with your public IP address. Clicking on the menu bar item will display a dropdown list with the following information:

- 🌍 **Public IP:** The public IP address of your current network.
- 💻 **Local IP (en0):** The local IP address of your primary network interface.
- **DNS Servers:** A list of DNS servers (both manually configured and DHCP/automatic).
- 📇 **ISP:** The ISP providing your Internet connection.
- 📍 **Country:** The country and country code based on the public IP.
- **Refresh:** A manual refresh option to update the displayed information immediately.

## Configuration

### Customizing the Refresh Interval

You can adjust the automatic refresh interval by modifying the `hs.timer.doEvery` value in the Spoon's `start()` function. By default, the menu refreshes every 60 seconds.

### Filtering Duplicate DNS Entries

The Spoon includes a built-in mechanism to filter out duplicate DNS entries. If you need to change this behavior, you can modify the `getDNSInfo()` function in the Spoon's `init.lua` file.

## Example

Here’s an example of how to load and start the Spoon in your `init.lua`:

```lua
hs.loadSpoon("NetworkInfo")
spoon.NetworkInfo:start()
```

## Troubleshooting

If you encounter issues such as incorrect or missing network information, try the following steps:

1. **Check Network Preferences:**

   - Ensure that your network interfaces are correctly configured in macOS **System Preferences > Network**.

2. **Review Logs:**

   - Check the Hammerspoon console for any error messages or logs that might indicate the source of the problem.

3. **DNS Configuration:**
   - If DNS entries appear incorrectly or duplicates persist, verify your DNS configuration using `scutil --dns` in the terminal.

## License

This Spoon is licensed under the MIT License. See the [LICENSE](https://opensource.org/licenses/MIT) file for more details.

## Author

- **James Turnbull** - [james@lovedthanlost.net](mailto:james@lovedthanlost.net)
- Thanks to [senorprogrammer](https://github.com/senorprogrammer) for the [DNS module](https://github.com/senorprogrammer/hammerspoon_init/blob/master/lib/dns.lua) and Sibin Arsenijević's PublicIP Spoon for heavy inspiration.
