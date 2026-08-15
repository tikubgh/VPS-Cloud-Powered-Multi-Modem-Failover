# VPS-Cloud-Powered-Multi-Modem-Failover
An elite, software-only multi-WAN load balancing and failover architecture designed to bridge Windows 11 networks to a cloud VPS.

It is an advanced network routing script that transforms any standard Linux VPS (including Oracle Ampere ARM64) into a hardened traffic-routing engine. By pairing a custom Shadowsocks-libev backend with the Windows Clash Verge Rev client, it creates a seamless 5-second automatic failover system across multiple internet connections—all without requiring you to open devices, flash custom router firmware, or rely on strictly wireless setups.

It actively monitors network traffic, bypasses ISP Deep Packet Inspection (DPI) to prevent video throttling, and hosts a live, auto-refreshing traffic dashboard.

✨ Elite Feature Set

⚡ Sub-5-Second Preemptive Failback: Instantly shifts traffic from your dead Primary ISP to backup USB Wi-Fi, RNDIS Modems, or Cellular Datacards. Automatically returns traffic to the Primary ISP the millisecond it comes back online.

🛡️ Zero Hardware Flashing: A 100% software-based solution. No custom router firmware or physical hardware modifications are required.

📊 Traffic-Aware Delta Engine Dashboard: A lightweight Python web server that calculates exact per-ISP byte flows, displaying real-time Active/Standby/Offline states and total data consumed (in MB/GB).

🚀 Anti-Throttling & DPI Bypass: Forces the Linux kernel to use Google's TCP BBR congestion control alongside chacha20-ietf-poly1305 encryption to mask high-bitrate video streams and bypass ISP speed throttling.

🏗️ Universal Architecture & OMR-Proof: Automatically detects AMD64/ARM64 and Ubuntu/Debian/CentOS. Includes aggressive conflict resolution to forcefully bypass OpenMPTCProuter (OMR) locked ports and firewalls.

🔒 Fixed Static Architecture: Utilizes a statically defined configuration and fixed passwords to ensure the system is reproducible, predictable, and stable across reboots.

🛠️ Installation Guide
The setup process is divided into two distinct parts: the Cloud VPS backend and the Windows 11 client frontend.

---------------------------------------------------------------------------------------------------------------------
Part 1: The VPS Deployment
Log into your VPS (Ubuntu, Debian, or CentOS) via SSH using a terminal like Bitvise.

Ensure you have root privileges (sudo su).

Copy and paste the entire master installation script directly into the terminal.

The script will automatically detect your OS, resolve port conflicts, install the proxy engine, apply TCP BBR, and launch the Python web dashboard.

Once finished, the terminal will output two URLs:

Your Windows Setup URL: http://YOUR_VPS_IP:8080/config.yaml

Your Live Dashboard URL: http://YOUR_VPS_IP:8080/

(Note: If you are using Oracle Cloud, you must manually open TCP/UDP port 8388 and TCP port 8080 in the external VCN Security Lists).

-----------------------------------------------------------------------------------------------------------
Part 2: The Windows 11 Client Setup
To route your PC's traffic through the new VPS engine, you will use Clash Verge Rev as the client.

Download and install Clash Verge Rev for Windows.
https://clashverges.org/en/download/

Open the application and navigate to Profiles on the left sidebar.

Paste your Windows Setup URL (http://YOUR_VPS_IP:8080/config.yaml) into the top search bar and click Import.

Right-click the newly imported profile and select Use.

Navigate to Settings on the left sidebar. Look for the Tun Mode section.

First-time setup: Click the blue Wrench Icon next to Tun Mode to install the Windows background service (accept the Administrator prompt).

Toggle Tun Mode to the ON position.

Navigate to the Home tab and ensure Proxy Mode is set strictly to Rule.

---------------------------------------------------------------------------------
FAQ:
If not working the match the wifi or ethernet adapter name same inside the setup script


You are fully connected. You can now plug in multiple USB Wi-Fi cards, Android/iPhone tethers, or MBIM Cellular modems. The system will automatically detect them, list them in your live dashboard, and instantly failover if your primary connection drops.
