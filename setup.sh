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

echo "=== 2. Securing Active SSH Session (Port $CURRENT_SSH_PORT) ==="
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
# AGGRESSIVE PACKAGE INSTALLATION
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
# WINDOWS APP CONFIGURATION (YAML Generator)
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
# ULTIMATE DASHBOARD (With Real-Time Speed Engine)
# -----------------------------------------------------------
cat > /opt/clash-config/dashboard.py << 'EOF_PYTHON'
import http.server, socketserver, subprocess, json, urllib.request, os, time, shutil

PORT = 8080
HISTORY_FILE = "isp_history.json"
prev_cpu_stat = None
LAST_ACTIVE_TIME = 0.0

# Speed tracking variables
LAST_NET_TIME = time.time()
LAST_RX = 0
LAST_TX = 0

def run_cmd(cmd):
    try:
        return subprocess.check_output(cmd, shell=True).decode().strip()
    except:
        return ""

def get_cpu_usage():
    global prev_cpu_stat
    try:
        with open("/proc/stat", "r") as f:
            fields = [float(column) for column in f.readline().strip().split()[1:]]
        idle_time = fields[3] + fields[4]
        total_time = sum(fields)
        if prev_cpu_stat is None:
            prev_cpu_stat = (idle_time, total_time)
            time.sleep(0.05)
            with open("/proc/stat", "r") as f:
                fields = [float(column) for column in f.readline().strip().split()[1:]]
            idle_time = fields[3] + fields[4]
            total_time = sum(fields)
        
        idle_delta = idle_time - prev_cpu_stat[0]
        total_delta = total_time - prev_cpu_stat[1]
        prev_cpu_stat = (idle_time, total_time)
        
        if total_delta > 0:
            cpu_pct = 100.0 * (1.0 - idle_delta / total_delta)
            return round(max(0.0, min(100.0, cpu_pct)), 1)
    except:
        pass
    return 0.0

def get_ram_usage():
    try:
        mem = {}
        with open("/proc/meminfo", "r") as f:
            for line in f:
                parts = line.split(":")
                if len(parts) == 2:
                    mem[parts[0].strip()] = int(parts[1].strip().split()[0])
        total = mem.get("MemTotal", 1)
        avail = mem.get("MemAvailable", mem.get("MemFree", 0))
        used = total - avail
        pct = (used / total) * 100.0
        used_gb = round(used / (1024 * 1024), 2)
        total_gb = round(total / (1024 * 1024), 2)
        return round(pct, 1), f"{used_gb} GB / {total_gb} GB"
    except:
        return 0.0, "0.0 GB / 0.0 GB"

def get_disk_usage():
    try:
        total, used, free = shutil.disk_usage("/")
        free_gb = round(free / (1024**3), 1)
        total_gb = round(total / (1024**3), 1)
        used_pct = round((used / total) * 100.0, 1)
        disk_str = f"{free_gb} GB Free / {total_gb} GB Total"
        return used_pct, disk_str
    except:
        return 0.0, "0 GB Free / 0 GB Total"

def get_established_ips():
    out = run_cmd("netstat -tn | grep :8388 | grep ESTABLISHED | awk '{print $5}' | cut -d: -f1")
    return list(set([ip for ip in out.split('\n') if ip and ip != "127.0.0.1" and ip != "0.0.0.0"]))

def get_isp_info(ip):
    try:
        req = urllib.request.urlopen(f"http://ip-api.com/json/{ip}?fields=status,country,city,isp,org", timeout=2)
        data = json.loads(req.read().decode())
        if data.get("status") == "fail":
            return "Private/Unknown", "Unknown", ""
        isp_name = data.get("isp") or data.get("org") or "Direct Connection"
        city = data.get("city") or "Unknown Location"
        country = data.get("country") or ""
        return isp_name, city, country
    except:
        return "Direct Connection", "Unknown Location", ""

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

def get_net_stats():
    try:
        iface = run_cmd("ip route get 8.8.8.8 | grep dev | awk -F'dev' '{print $2}' | awk '{print $1}'")
        rx = int(open(f"/sys/class/net/{iface}/statistics/rx_bytes").read().strip())
        tx = int(open(f"/sys/class/net/{iface}/statistics/tx_bytes").read().strip())
        return rx, tx
    except:
        return 0, 0

def format_speed(bps):
    if bps < 1024:
        return f"{int(bps)} B/s"
    elif bps < 1024 * 1024:
        return f"{round(bps / 1024, 1)} KB/s"
    else:
        return f"{round(bps / (1024 * 1024), 2)} MB/s"

class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/config.yaml':
            super().do_GET()
        elif self.path == '/api/data':
            global LAST_ACTIVE_TIME, LAST_NET_TIME, LAST_RX, LAST_TX
            current_time = time.time()
            
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.end_headers()
            
            active_socket_ips = get_established_ips()
            for ip in active_socket_ips:
                setup_iptables_tracking(ip)
                
            history = {}
            if os.path.exists(HISTORY_FILE):
                try:
                    with open(HISTORY_FILE, "r") as f:
                        history = json.loads(f.read())
                except:
                    pass
            
            for ip in active_socket_ips:
                if ip not in history:
                    isp_name, city, country = get_isp_info(ip)
                    history[ip] = {
                        "isp_name": isp_name,
                        "city": city,
                        "country": country,
                        "current_ip": ip,
                        "last_bytes": get_raw_bytes(ip),
                        "total_bytes": 0,
                        "is_active": False,
                        "is_online": True
                    }
                else:
                    history[ip]["is_online"] = True
            
            total_delta = 0
            max_delta = -1
            best_ip = None
            
            for ip in list(history.keys()):
                current_bytes = get_raw_bytes(ip)
                last_bytes = history[ip].get("last_bytes", current_bytes)
                delta = max(0, current_bytes - last_bytes)
                total_delta += delta
                
                history[ip]["last_bytes"] = current_bytes
                history[ip]["total_bytes"] = current_bytes
                history[ip]["total_formatted"] = format_bytes(current_bytes)
                history[ip]["is_online"] = (ip in active_socket_ips)
                
                if history[ip]["is_online"] and delta > max_delta:
                    max_delta = delta
                    best_ip = ip
                    
            if total_delta > 5000:
                LAST_ACTIVE_TIME = current_time
                
            is_client_online = (current_time - LAST_ACTIVE_TIME) < 30
            
            if not is_client_online:
                history = {}
                if os.path.exists(HISTORY_FILE):
                    try: os.remove(HISTORY_FILE)
                    except: pass
            else:
                prev_active = None
                for ip in history:
                    if history[ip].get("is_active"):
                        prev_active = ip
                        break
                        
                if max_delta < 5000 and prev_active and history.get(prev_active, {}).get("is_online"):
                    best_ip = prev_active
                elif not best_ip and len(active_socket_ips) > 0:
                    best_ip = active_socket_ips[0]
                    
                for ip in history:
                    history[ip]["is_active"] = (ip == best_ip and history[ip]["is_online"])
                    
                with open(HISTORY_FILE, "w") as f:
                    f.write(json.dumps(history))
            
            # --- System Metrics & Speed Engine ---
            cpu_pct = get_cpu_usage()
            ram_pct, ram_str = get_ram_usage()
            disk_pct, disk_str = get_disk_usage()
            
            rx, tx = get_net_stats()
            if LAST_RX == 0 and LAST_TX == 0:
                LAST_RX, LAST_TX = rx, tx
            
            time_diff = current_time - LAST_NET_TIME
            rx_speed = (rx - LAST_RX) / time_diff if time_diff > 0 else 0
            tx_speed = (tx - LAST_TX) / time_diff if time_diff > 0 else 0
            
            LAST_RX, LAST_TX = rx, tx
            LAST_NET_TIME = current_time
            
            total_traffic = round((rx + tx) / (1024**3), 2)

            payload = {
                "cpu_pct": cpu_pct,
                "ram_pct": ram_pct,
                "ram_str": ram_str,
                "disk_pct": disk_pct,
                "disk_str": disk_str,
                "total_traffic": total_traffic,
                "dl_speed": format_speed(rx_speed),
                "ul_speed": format_speed(tx_speed),
                "is_client_online": is_client_online,
                "isps": list(history.values())
            }
            self.wfile.write(json.dumps(payload).encode("utf-8"))
        else:
            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
            
            html = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NexusWAN Sentinel Live Telemetry</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background: #0B0F19; color: #F1F5F9; height: 100vh; overflow: hidden; display: flex; flex-direction: column; }
        
        .app-container { height: 100vh; max-width: 1400px; width: 100%; margin: 0 auto; padding: 16px 20px; display: flex; flex-direction: column; gap: 12px; }
        
        .header { display: flex; justify-content: space-between; align-items: center; padding-bottom: 8px; border-bottom: 1px solid #1E293B; }
        .header h1 { font-size: 20px; font-weight: 700; color: #38BDF8; letter-spacing: 0.5px; }
        .header-status { font-size: 13px; font-weight: 600; padding: 4px 10px; border-radius: 6px; }
        .hs-connected { background: rgba(16, 185, 129, 0.15); color: #34D399; border: 1px solid #10B981; }
        .hs-disconnected { background: rgba(239, 68, 68, 0.15); color: #F87171; border: 1px solid #EF4444; }

        .metrics-row { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; }
        .m-card { background: #131C2E; border-radius: 10px; padding: 12px 14px; border: 1px solid #1E293B; }
        .m-title { font-size: 11px; font-weight: 700; text-transform: uppercase; color: #94A3B8; letter-spacing: 0.5px; }
        .m-val-row { display: flex; justify-content: space-between; align-items: baseline; margin: 4px 0 6px 0; }
        .m-val { font-size: 20px; font-weight: 800; font-family: monospace; color: #F8FAFC; }
        .m-sub { font-size: 11px; color: #64748B; font-family: monospace; }
        
        .speed-row { display: flex; justify-content: space-between; font-size: 11px; font-family: monospace; margin-bottom: 4px; }
        .dl-text { color: #10B981; font-weight: 700; }
        .ul-text { color: #38BDF8; font-weight: 700; }

        .p-bg { background: #0B0F19; height: 6px; border-radius: 3px; overflow: hidden; }
        .p-fill { height: 100%; border-radius: 3px; transition: width 0.4s ease; }
        .f-cpu { background: #38BDF8; }
        .f-ram { background: #A855F7; }
        .f-disk { background: #EC4899; }
        .f-traffic { background: #10B981; }

        .isp-section { flex: 1; display: flex; flex-direction: column; overflow: hidden; }
        .isp-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 12px; height: 100%; overflow-y: auto; align-content: start; }
        
        .isp-card { background: #131C2E; border-radius: 10px; padding: 14px 16px; border: 1px solid #1E293B; border-left: 6px solid #475569; position: relative; display: flex; flex-direction: column; justify-content: space-between; }
        .isp-card.active { border-left-color: #10B981; box-shadow: 0 0 15px rgba(16, 185, 129, 0.15); }
        .isp-card.standby { border-left-color: #F59E0B; }
        
        .card-head { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 10px; }
        .isp-name { font-size: 16px; font-weight: 700; color: #F8FAFC; }
        .badge { padding: 3px 8px; border-radius: 12px; font-size: 10px; font-weight: 800; text-transform: uppercase; }
        .b-active { background: rgba(16, 185, 129, 0.2); color: #10B981; border: 1px solid #10B981; }
        .b-standby { background: rgba(245, 158, 11, 0.2); color: #F59E0B; border: 1px solid #F59E0B; }
        
        .d-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; font-size: 12px; margin-bottom: 8px; }
        .d-box { background: #0B0F19; padding: 6px 10px; border-radius: 6px; }
        .d-lbl { color: #64748B; font-size: 10px; text-transform: uppercase; }
        .d-txt { color: #F1F5F9; font-weight: 600; font-family: monospace; }
        .highlight { color: #38BDF8; font-weight: 700; }

        .empty-state { height: 100%; display: flex; flex-direction: column; align-items: center; justify-content: center; background: #131C2E; border: 1px dashed #334155; border-radius: 10px; text-align: center; padding: 20px; }
        .empty-state svg { width: 54px; height: 54px; color: #F87171; margin-bottom: 16px; }
        .empty-state h3 { font-size: 24px; color: #F87171; margin-bottom: 8px; font-weight: 800; letter-spacing: 1px; }
        .empty-state p { font-size: 14px; color: #94A3B8; max-width: 450px; line-height: 1.5; }
    </style>
</head>
<body>
    <div class="app-container">
        <div class="header">
            <h1>NexusWAN Sentinel Dashboard</h1>
            <div id="status-badge" class="header-status hs-disconnected">INITIALIZING...</div>
        </div>

        <div class="metrics-row">
            <div class="m-card">
                <div class="m-title">VPS CPU Load</div>
                <div class="m-val-row"><span id="cpu-val" class="m-val">0.0%</span><span class="m-sub">Live</span></div>
                <div class="p-bg"><div id="cpu-bar" class="p-fill f-cpu" style="width: 0%;"></div></div>
            </div>
            <div class="m-card">
                <div class="m-title">RAM Usage</div>
                <div class="m-val-row"><span id="ram-val" class="m-val">0.0%</span><span id="ram-sub" class="m-sub">--</span></div>
                <div class="p-bg"><div id="ram-bar" class="p-fill f-ram" style="width: 0%;"></div></div>
            </div>
            <div class="m-card">
                <div class="m-title">Disk Storage</div>
                <div class="m-val-row"><span id="disk-val" class="m-val">0.0%</span><span id="disk-sub" class="m-sub">--</span></div>
                <div class="p-bg"><div id="disk-bar" class="p-fill f-disk" style="width: 0%;"></div></div>
            </div>
            <div class="m-card">
                <div class="m-title">VPS Traffic & Speed</div>
                <div class="m-val-row" style="margin-bottom:2px;"><span id="traffic-val" class="m-val">0.0 GB</span><span class="m-sub">Total</span></div>
                <div class="speed-row">
                    <span>↓ <span id="dl-speed" class="dl-text">0.0 KB/s</span></span>
                    <span>↑ <span id="ul-speed" class="ul-text">0.0 KB/s</span></span>
                </div>
                <div class="p-bg"><div class="p-fill f-traffic" style="width: 100%;"></div></div>
            </div>
        </div>

        <div class="isp-section">
            <div id="isp-container" class="isp-grid"></div>
        </div>
    </div>

    <script>
        async function fetchTelemetry() {
            try {
                const res = await fetch('/api/data', { cache: 'no-store' });
                const d = await res.json();

                document.getElementById('cpu-val').innerText = d.cpu_pct + '%';
                document.getElementById('cpu-bar').style.width = Math.min(d.cpu_pct, 100) + '%';

                document.getElementById('ram-val').innerText = d.ram_pct + '%';
                document.getElementById('ram-sub').innerText = d.ram_str;
                document.getElementById('ram-bar').style.width = Math.min(d.ram_pct, 100) + '%';

                document.getElementById('disk-val').innerText = d.disk_pct + '%';
                document.getElementById('disk-sub').innerText = d.disk_str;
                document.getElementById('disk-bar').style.width = Math.min(d.disk_pct, 100) + '%';

                // Speed Metrics applied
                document.getElementById('traffic-val').innerText = d.total_traffic + ' GB';
                document.getElementById('dl-speed').innerText = d.dl_speed;
                document.getElementById('ul-speed').innerText = d.ul_speed;

                const sb = document.getElementById('status-badge');
                if (d.is_client_online) {
                    sb.className = 'header-status hs-connected';
                    sb.innerText = '● CLIENT CONNECTED (TUN ACTIVE)';
                } else {
                    sb.className = 'header-status hs-disconnected';
                    sb.innerText = '● NO CONNECTION TO PC (TUN OFF / IDLE)';
                }

                const container = document.getElementById('isp-container');
                if (!d.is_client_online || !d.isps || d.isps.length === 0) {
                    container.innerHTML = `
                        <div class="empty-state">
                            <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M18.364 5.636a9 9 0 010 12.728m0 0l-2.829-2.829m2.829 2.829L21 21M15.536 8.464a5 5 0 010 7.072m0 0l-2.829-2.829m-4.243 2.829a4.978 4.978 0 01-1.414-2.83m-1.414 5.658a9 9 0 01-2.167-9.238m7.824 2.167a1 1 0 111.414 1.414m-1.414-1.414L3 3m8.293 8.293l1.414 1.414"></path></svg>
                            <h3>ALL CONNECTIONS OFF</h3>
                            <p>System is in Standby Mode. Turn ON <b>TUN Mode</b> in your local client to restore encrypted routing.</p>
                        </div>
                    `;
                    return;
                }

                let cardsHtml = '';
                d.isps.forEach((isp, idx) => {
                    const isActive = isp.is_active;
                    const cardClass = isActive ? 'isp-card active' : 'isp-card standby';
                    const badgeClass = isActive ? 'badge b-active' : 'badge b-standby';
                    const badgeText = isActive ? '● ACTIVE NOW' : '● STANDBY';

                    cardsHtml += `
                        <div class="${cardClass}">
                            <div>
                                <div class="card-head">
                                    <div class="isp-name">ISP ${idx + 1}: ${isp.isp_name}</div>
                                    <span class="${badgeClass}">${badgeText}</span>
                                </div>
                                <div class="d-grid">
                                    <div class="d-box">
                                        <div class="d-lbl">Active IP</div>
                                        <div class="d-txt">${isp.current_ip}</div>
                                    </div>
                                    <div class="d-box">
                                        <div class="d-lbl">Location</div>
                                        <div class="d-txt">${isp.city || 'Unknown'}, ${isp.country || ''}</div>
                                    </div>
                                    <div class="d-box" style="grid-column: span 2;">
                                        <div class="d-lbl">Data Processed by ISP</div>
                                        <div class="d-txt highlight">${isp.total_formatted || '0.00 MB'}</div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    `;
                });
                container.innerHTML = cardsHtml;
            } catch (err) {
                console.error("Telemetry fetch error:", err);
            }
        }

        fetchTelemetry();
        setInterval(fetchTelemetry, 2000);
    </script>
</body>
</html>
"""
            self.wfile.write(html.encode("utf-8"))

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
echo "=========================================================================="
echo "✅ NEXUSWAN SENTINEL DEPLOYED & CONFIGURED SUCCESSFULLY!"
echo "=========================================================================="
echo "Architecture Detected : $SYSTEM_ARCH"
echo "Operating System      : $OS $OS_VERSION"
echo "Server Public IPv4    : $SERVER_IP"
echo "Shadowsocks Port      : $SS_PORT"
echo "Dashboard Port        : $HTTP_PORT"
echo "=========================================================================="
echo "👉 1. CLIENT SUBSCRIPTION URL (Import into Clash Verge Rev):"
echo "   http://${SERVER_IP}:${HTTP_PORT}/config.yaml"
echo ""
echo "👉 2. LIVE TELEMETRY DASHBOARD (Open in Any Browser):"
echo "   http://${SERVER_IP}:${HTTP_PORT}/"
echo "=========================================================================="
echo ""
EOF

bash setup.sh
