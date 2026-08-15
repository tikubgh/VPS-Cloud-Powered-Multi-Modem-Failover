rm -f setup.sh

cat > setup.sh << 'EOF'
#!/bin/bash
set -e

echo "============================================================"
echo "=== 1. Starting Universal OS & Architecture Detection ==="
echo "============================================================"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) SYSTEM_ARCH="AMD64" ;;
    aarch64|arm64) SYSTEM_ARCH="ARM64" ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac
echo "✅ Architecture detected: $SYSTEM_ARCH"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
else
    echo "❌ Cannot determine OS."
    exit 1
fi
echo "✅ Operating System detected: $OS (Version: $OS_VERSION)"

# -----------------------------------------------------------
# SAFETY LAYER: Keep SSH Alive
# -----------------------------------------------------------
CURRENT_SSH_PORT=$(echo $SSH_CLIENT | awk '{print $3}')
if [ -z "$CURRENT_SSH_PORT" ]; then CURRENT_SSH_PORT=22; fi

iptables -I INPUT 1 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
iptables -I INPUT 2 -p tcp --dport $CURRENT_SSH_PORT -j ACCEPT 2>/dev/null || true

# -----------------------------------------------------------
# CRITICAL REPAIR & OMR CONFLICT RESOLUTION
# -----------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

dpkg --configure -a || true
apt-get --fix-broken install -yq || true

SS_PORT=8388
HTTP_PORT=8080

apt-get update -yq >/dev/null 2>&1 || true
apt-get install -yq psmisc >/dev/null 2>&1 || true

fuser -k ${SS_PORT}/tcp >/dev/null 2>&1 || true
fuser -k ${SS_PORT}/udp >/dev/null 2>&1 || true
fuser -k ${HTTP_PORT}/tcp >/dev/null 2>&1 || true
sleep 2

# -----------------------------------------------------------
# AGGRESSIVE PACKAGE INSTALLATION (FORCE OVERWRITE)
# -----------------------------------------------------------
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]] || [[ "$OS" == "openmptcprouter" ]]; then
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    mkdir -p /etc/needrestart/conf.d/
    echo '$nrconf{override_rc}{qr(^ssh(d)?\.service$)} = 0;' > /etc/needrestart/conf.d/keep-ssh.conf 2>/dev/null || true

    apt-get install -yq -o Dpkg::Options::="--force-overwrite" shadowsocks-libev python3 curl iptables-persistent ufw net-tools iproute2

elif [[ "$OS" == "centos" ]] || [[ "$OS" == "almalinux" ]] || [[ "$OS" == "rocky" ]]; then
    yum install -y epel-release
    yum install -y shadowsocks-libev python3 curl iptables net-tools iproute firewalld
    systemctl enable firewalld --now || true
fi

# -----------------------------------------------------------
# OMR-SAFE ANTI-THROTTLING & DPI BYPASS
# -----------------------------------------------------------
grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1 || true

# -----------------------------------------------------------
# PROXY ENGINE SETUP
# -----------------------------------------------------------
SERVER_IP=$(curl -4s https://ifconfig.me 2>/dev/null || curl -4s https://api.ipify.org 2>/dev/null)
if [ -z "$SERVER_IP" ]; then SERVER_IP=$(hostname -I | awk '{print $1}'); fi

SS_PASSWORD="MyFixedSecurePassword123"
SS_METHOD="chacha20-ietf-poly1305"

mkdir -p /etc/shadowsocks-libev
cat > /etc/shadowsocks-libev/config.json << EOL2
{
    "server":"0.0.0.0",
    "server_port":${SS_PORT},
    "local_port":1080,
    "password":"${SS_PASSWORD}",
    "timeout":300,
    "method":"${SS_METHOD}",
    "mode":"tcp_and_udp",
    "fast_open":true
}
EOL2

systemctl restart shadowsocks-libev
systemctl enable shadowsocks-libev

# -----------------------------------------------------------
# WINDOWS APP CONFIGURATION (Dynamic Wi-Fi Naming)
# -----------------------------------------------------------
mkdir -p /opt/clash-config
cat > /opt/clash-config/config.yaml << EOL2
port: 7890
socks-port: 7891
allow-lan: true
mode: rule
log-level: info
ipv6: false

tun:
  enable: true
  stack: system
  auto-route: true
  auto-detect-interface: true

proxies:
  - name: "Priority 1 (Primary - WiFi no hyphen)"
    type: ss
    server: ${SERVER_IP}
    port: ${SS_PORT}
    cipher: ${SS_METHOD}
    password: "${SS_PASSWORD}"
    udp: true
    interface-name: "WiFi"

  - name: "Priority 2 (Backup - WiFi 2 no hyphen)"
    type: ss
    server: ${SERVER_IP}
    port: ${SS_PORT}
    cipher: ${SS_METHOD}
    password: "${SS_PASSWORD}"
    udp: true
    interface-name: "WiFi 2"

  - name: "Priority 3 (Backup - Wi-Fi 2 with hyphen)"
    type: ss
    server: ${SERVER_IP}
    port: ${SS_PORT}
    cipher: ${SS_METHOD}
    password: "${SS_PASSWORD}"
    udp: true
    interface-name: "Wi-Fi 2"

  - name: "Priority 4 (Backup - RNDIS/Android/iPhone Tether 1)"
    type: ss
    server: ${SERVER_IP}
    port: ${SS_PORT}
    cipher: ${SS_METHOD}
    password: "${SS_PASSWORD}"
    udp: true
    interface-name: "Ethernet 2"

  - name: "Priority 5 (Backup - RNDIS/Android/iPhone Tether 2)"
    type: ss
    server: ${SERVER_IP}
    port: ${SS_PORT}
    cipher: ${SS_METHOD}
    password: "${SS_PASSWORD}"
    udp: true
    interface-name: "Ethernet 3"

  - name: "Priority 6 (Backup - MBIM Cellular Modem)"
    type: ss
    server: ${SERVER_IP}
    port: ${SS_PORT}
    cipher: ${SS_METHOD}
    password: "${SS_PASSWORD}"
    udp: true
    interface-name: "Cellular"

  - name: "Priority 7 (Fallback - Main Ethernet Cable)"
    type: ss
    server: ${SERVER_IP}
    port: ${SS_PORT}
    cipher: ${SS_METHOD}
    password: "${SS_PASSWORD}"
    udp: true
    interface-name: "Ethernet"

proxy-groups:
  - name: "Strict-Active-Backup"
    type: fallback
    proxies:
      - "Priority 1 (Primary - WiFi no hyphen)"
      - "Priority 2 (Backup - WiFi 2 no hyphen)"
      - "Priority 3 (Backup - Wi-Fi 2 with hyphen)"
      - "Priority 4 (Backup - RNDIS/Android/iPhone Tether 1)"
      - "Priority 5 (Backup - RNDIS/Android/iPhone Tether 2)"
      - "Priority 6 (Backup - MBIM Cellular Modem)"
      - "Priority 7 (Fallback - Main Ethernet Cable)"
    url: 'http://www.gstatic.com/generate_204'
    interval: 5        
    timeout: 2000      

rules:
  - MATCH, Strict-Active-Backup
EOL2

# -----------------------------------------------------------
# ADVANCED DASHBOARD WEB SERVER (Traffic Delta Engine)
# -----------------------------------------------------------
cat > /opt/clash-config/dashboard.py << 'EOF_PYTHON'
import http.server, socketserver, subprocess, json, urllib.request, os

PORT = 8080
HISTORY_FILE = "isp_history.json"

def run_cmd(cmd):
    try:
        return subprocess.check_output(cmd, shell=True).decode().strip()
    except:
        return ""

def get_new_ips():
    out = run_cmd("netstat -tn | grep :8388 | awk '{print $5}' | cut -d: -f1")
    return list(set([ip for ip in out.split('\n') if ip and ip != "127.0.0.1" and ip != "0.0.0.0"]))

def get_isp_info(ip):
    try:
        req = urllib.request.urlopen(f"http://ip-api.com/json/{ip}?fields=status,country,city,isp", timeout=2)
        return json.loads(req.read().decode())
    except:
        return {"isp": "Unknown ISP", "city": "Unknown", "country": "Unknown"}

def setup_iptables_tracking(ip):
    check = run_cmd(f"iptables -nL INPUT | grep '{ip} ' || true")
    if not check:
        run_cmd(f"iptables -I INPUT -s {ip} -j ACCEPT")
        run_cmd(f"iptables -I OUTPUT -d {ip} -j ACCEPT")

def get_raw_bytes(ip):
    try:
        in_bytes = run_cmd(f"iptables -nxvL INPUT | grep '{ip} ' | awk '{{print $2}}'")
        in_sum = sum([int(b) for b in in_bytes.split('\n') if b.isdigit()])
        out_bytes = run_cmd(f"iptables -nxvL OUTPUT | grep '{ip} ' | awk '{{print $2}}'")
        out_sum = sum([int(b) for b in out_bytes.split('\n') if b.isdigit()])
        return in_sum + out_sum
    except:
        return 0

def format_bytes(b):
    mb = b / (1024 * 1024)
    if mb > 1024:
        return f"{round(mb / 1024, 2)} GB"
    return f"{round(mb, 2)} MB"

def get_total_traffic():
    try:
        iface = run_cmd("ip route get 8.8.8.8 | grep dev | awk -F'dev' '{print $2}' | awk '{print $1}'")
        rx = int(open(f"/sys/class/net/{iface}/statistics/rx_bytes").read().strip())
        tx = int(open(f"/sys/class/net/{iface}/statistics/tx_bytes").read().strip())
        return round((rx + tx) / (1024**3), 2)
    except:
        return 0.0

class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/config.yaml':
            super().do_GET()
        else:
            try:
                history = {}
                if os.path.exists(HISTORY_FILE):
                    with open(HISTORY_FILE, "r") as f:
                        history = json.loads(f.read())
                
                # Register any new IPs
                new_ips = get_new_ips()
                for ip in new_ips:
                    if ip not in history:
                        history[ip] = get_isp_info(ip)
                        history[ip]["last_bytes"] = 0
                        history[ip]["is_active"] = False
                    setup_iptables_tracking(ip)

                # Calculate True Traffic Deltas (Bytes per 5 seconds)
                deltas = {}
                for ip in history:
                    current_bytes = get_raw_bytes(ip)
                    last_bytes = history[ip].get("last_bytes", current_bytes)
                    deltas[ip] = current_bytes - last_bytes
                    history[ip]["last_bytes"] = current_bytes
                    history[ip]["total_formatted"] = format_bytes(current_bytes)

                # Active/Standby/Offline Logic Engine
                max_delta = -1
                best_ip = None
                for ip, delta in deltas.items():
                    if delta > max_delta:
                        max_delta = delta
                        best_ip = ip
                
                previous_active = None
                for ip in history:
                    if history[ip].get("is_active"):
                        previous_active = ip
                        break
                
                active_ip = None
                if max_delta < 1500: # Less than 1.5KB means it's just idle health-check pings
                    if previous_active and deltas.get(previous_active, 0) > 0:
                        active_ip = previous_active
                    else:
                        active_ip = best_ip
                else:
                    active_ip = best_ip

                for ip in history:
                    history[ip]["is_active"] = (ip == active_ip)
                    history[ip]["is_dead"] = (deltas.get(ip, 0) == 0) # Zero bytes = completely offline

                with open(HISTORY_FILE, "w") as f:
                    f.write(json.dumps(history))

                traffic_gb = get_total_traffic()

                # Build HTML UI
                html = f"""
                <!DOCTYPE html>
                <html lang="en">
                <head>
                    <meta charset="UTF-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <title>Multi-WAN Failover Dashboard</title>
                    <meta http-equiv="refresh" content="5">
                    <style>
                        body {{ font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background: #0F172A; color: #F8FAFC; padding: 20px; margin: 0; }}
                        .header {{ text-align: center; margin-bottom: 30px; border-bottom: 1px solid #334155; padding-bottom: 20px; }}
                        .header h1 {{ color: #38BDF8; font-size: 28px; font-weight: 600; margin: 0; text-transform: uppercase; letter-spacing: 1px; }}
                        .container {{ max-width: 900px; margin: auto; }}
                        .grid {{ display: grid; grid-template-columns: 1fr; gap: 20px; }}
                        
                        .card {{ background: #1E293B; border-radius: 12px; padding: 24px; position: relative; border-left: 8px solid #475569; box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.5); }}
                        .card.active {{ border-left-color: #10B981; box-shadow: 0 0 20px rgba(16, 185, 129, 0.2); }}
                        .card.offline {{ border-left-color: #EF4444; opacity: 0.7; }}
                        
                        .traffic-card {{ background: linear-gradient(145deg, #1E293B, #0F172A); border-left: 8px solid #38BDF8; text-align: center; padding: 30px; }}
                        .traffic-card h2 {{ margin: 10px 0 0 0; color: #38BDF8; font-size: 42px; font-weight: 700; }}
                        .traffic-card p {{ margin: 0; color: #94A3B8; font-size: 16px; text-transform: uppercase; letter-spacing: 1px; }}

                        .badge {{ position: absolute; top: 24px; right: 24px; padding: 6px 12px; border-radius: 20px; font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; }}
                        .badge-active {{ background: rgba(16, 185, 129, 0.2); color: #10B981; border: 1px solid #10B981; }}
                        .badge-standby {{ background: rgba(245, 158, 11, 0.2); color: #F59E0B; border: 1px solid #F59E0B; }}
                        .badge-offline {{ background: rgba(239, 68, 68, 0.2); color: #EF4444; border: 1px solid #EF4444; }}
                        
                        .isp-title {{ font-size: 22px; font-weight: 600; color: #F1F5F9; margin: 0 0 15px 0; padding-right: 100px; }}
                        
                        .data-row {{ display: flex; justify-content: space-between; align-items: center; background: #0F172A; padding: 12px 16px; border-radius: 8px; margin-bottom: 8px; }}
                        .data-label {{ color: #94A3B8; font-size: 14px; }}
                        .data-value {{ color: #F8FAFC; font-weight: 500; font-family: monospace; font-size: 15px; }}
                        .highlight-data {{ color: #38BDF8; font-weight: 700; font-size: 18px; }}
                    </style>
                </head>
                <body>
                    <div class="container">
                        <div class="header">
                            <h1>Network Failover Status</h1>
                        </div>
                        <div class="card traffic-card" style="margin-bottom: 30px;">
                            <p>Total Server Bandwidth Processed</p>
                            <h2>{traffic_gb} GB</h2>
                        </div>
                        <div class="grid">
                """

                if not history:
                    html += "<div class='card'><div class='isp-title'>Waiting for Windows PC to connect...</div></div>"
                
                isp_counter = 1
                for ip, info in history.items():
                    if info.get("is_active"):
                        card_class = "card active"
                        badge_class = "badge badge-active"
                        status_text = "● ACTIVE NOW"
                    elif info.get("is_dead"):
                        card_class = "card offline"
                        badge_class = "badge badge-offline"
                        status_text = "● OFFLINE"
                    else:
                        card_class = "card"
                        badge_class = "badge badge-standby"
                        status_text = "● STANDBY"
                    
                    isp_name = info.get("isp", "Unknown ISP")
                    city = info.get("city", "Unknown")
                    country = info.get("country", "")
                    location = f"{city}, {country}".strip(", ")
                    isp_traffic = info.get("total_formatted", "0.00 MB")
                    
                    html += f"""
                            <div class="{card_class}">
                                <div class="{badge_class}">{status_text}</div>
                                <div class="isp-title">ISP {isp_counter}: {isp_name}</div>
                                <div class="data-row">
                                    <span class="data-label">External IP Address</span>
                                    <span class="data-value">{ip}</span>
                                </div>
                                <div class="data-row">
                                    <span class="data-label">Physical Location</span>
                                    <span class="data-value">{location}</span>
                                </div>
                                <div class="data-row">
                                    <span class="data-label">Data Consumed by this ISP</span>
                                    <span class="data-value highlight-data">{isp_traffic}</span>
                                </div>
                            </div>
                    """
                    isp_counter += 1

                html += """
                        </div>
                    </div>
                </body>
                </html>
                """
                self.send_response(200)
                self.send_header("Content-type", "text/html; charset=utf-8")
                self.end_headers()
                self.wfile.write(html.encode("utf-8"))
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode("utf-8"))

socketserver.TCPServer.allow_reuse_address = True
httpd = socketserver.TCPServer(("", PORT), DashboardHandler)
httpd.serve_forever()
EOF_PYTHON

cat > /etc/systemd/system/clash-config-server.service << EOL2
[Unit]
Description=Clash Web Server & Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/clash-config
ExecStart=/usr/bin/python3 dashboard.py
Restart=always

[Install]
WantedBy=multi-user.target
EOL2

systemctl daemon-reload
systemctl enable clash-config-server
systemctl restart clash-config-server

# -----------------------------------------------------------
# AGGRESSIVE OMR FIREWALL OVERRIDES
# -----------------------------------------------------------
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]] || [[ "$OS" == "openmptcprouter" ]]; then
    iptables -I INPUT 1 -p tcp --dport ${SS_PORT} -j ACCEPT 2>/dev/null || true
    iptables -I INPUT 1 -p udp --dport ${SS_PORT} -j ACCEPT 2>/dev/null || true
    iptables -I INPUT 1 -p tcp --dport ${HTTP_PORT} -j ACCEPT 2>/dev/null || true
    netfilter-persistent save >/dev/null 2>&1 || true

elif [[ "$OS" == "centos" ]] || [[ "$OS" == "almalinux" ]] || [[ "$OS" == "rocky" ]]; then
    firewall-cmd --permanent --add-port=${SS_PORT}/tcp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port=${SS_PORT}/udp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port=${HTTP_PORT}/tcp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
fi

echo ""
echo "=========================================================="
echo "✅ Installation Completed! (Traffic-Aware Dashboard Live)"
echo "=========================================================="
echo "👉 Your Windows Setup URL (Paste into Clash Verge Rev):"
echo "http://${SERVER_IP}:${HTTP_PORT}/config.yaml"
echo "=========================================================="
echo ""
EOF

bash setup.sh
