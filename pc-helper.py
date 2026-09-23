#!/usr/bin/env python3
"""
AmfetamineB PC Helper (v0.1.4)
==============================
Cross-platform companion application for AmfetamineB iOS.
Pairs iOS device over USB, extracts pairing records, and
automatically deploys them into the AmfetamineB app container.
"""

import sys
import os
import json
import socket
import struct
import plistlib
import platform
import threading
import asyncio
import time
import urllib.request
import webbrowser
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

HTTP_PORT = 5988
IPHONE_SYNC_PORT = 8765

CANDIDATE_BUNDLE_IDS = [
    "com.mak5er.amfetamineb",
    "com.mak5er.amfetaboard",
    "com.mak5er.amfetaspoit",
    "com.mak5er.aircard",
    "com.mak5er.aircard-ios",
    "com.amfetamineb.app"
]

# ---------------------------------------------------------------------------
# Device & Pairing Logic
# ---------------------------------------------------------------------------

def get_usbmux_socket():
    system = platform.system()
    try:
        if system == "Windows":
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.connect(("127.0.0.1", 27015))
            return s
        else:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect("/var/run/usbmuxd")
            return s
    except Exception:
        return None

def usbmux_send_packet(sock, payload_dict):
    payload = plistlib.dumps(payload_dict)
    header = struct.pack("<IIII", len(payload) + 16, 1, 8, 1)
    sock.sendall(header + payload)

def usbmux_recv_packet(sock):
    header = sock.recv(16)
    if len(header) < 16:
        return None
    length, version, msg_type, tag = struct.unpack("<IIII", header)
    payload_len = length - 16
    payload = b""
    while len(payload) < payload_len:
        chunk = sock.recv(payload_len - len(payload))
        if not chunk:
            break
        payload += chunk
    if payload:
        try:
            return plistlib.loads(payload)
        except Exception:
            return None
    return None

def list_connected_devices():
    """Query usbmuxd for connected devices."""
    devices = []
    s = get_usbmux_socket()
    if s:
        try:
            req = {
                "MessageType": "ListDevices",
                "ClientVersionString": "AmfetamineB-PCHelper",
                "ProgName": "AmfetamineB"
            }
            usbmux_send_packet(s, req)
            res = usbmux_recv_packet(s)
            s.close()
            if res and "DeviceList" in res:
                for d in res["DeviceList"]:
                    props = d.get("Properties", {})
                    udid = props.get("SerialNumber", "")
                    dev_id = props.get("DeviceID", 0)
                    conn_type = props.get("ConnectionType", "USB")
                    if udid:
                        devices.append({
                            "udid": udid,
                            "deviceId": dev_id,
                            "connectionType": conn_type,
                            "name": f"iPhone ({conn_type})"
                        })
        except Exception:
            pass

    return devices

async def auto_pair_and_push_async(udid=None):
    """Pair device and push pairing records into the app container."""
    logs = []
    plist_bytes = None

    try:
        from pymobiledevice3.lockdown import create_using_usbmux
        from pymobiledevice3.services.house_arrest import HouseArrestService
    except ImportError:
        return False, "pymobiledevice3 library not found", logs, None

    # Step 1: Connect to Lockdown
    lockdown = None
    serial_candidates = [udid, udid.replace("-", "") if udid else None, None] if udid else [None]
    for s in serial_candidates:
        try:
            lockdown = await create_using_usbmux(serial=s) if s else await create_using_usbmux()
            if lockdown:
                break
        except Exception:
            continue

    if not lockdown:
        logs.append("[-] Device not found over USB. Ensure iPhone is unlocked and connected.")
        return False, "Device not found. Unlock iPhone and reconnect USB cable.", logs, None

    try:
        dev_name = await lockdown.get_value(key="DeviceName") or "iPhone"
        ios_ver = await lockdown.get_value(key="ProductVersion") or ""
        logs.append(f"[+] Connected to {dev_name} (iOS {ios_ver})")
    except Exception:
        logs.append("[+] Connected to iOS device")

    # Step 2: Extract Pairing Record & Enable Wi-Fi Sync
    try:
        pair_rec = lockdown.pair_record
        if not pair_rec:
            return False, "Device is not paired. Unlock iPhone and tap 'Trust This Computer'.", logs, None
        plist_bytes = plistlib.dumps(pair_rec)
        logs.append(f"[+] Pairing record extracted ({len(plist_bytes)} bytes)")

        try:
            await lockdown.set_value(value=True, domain="com.apple.mobile.wireless_lockdown", key="EnableWifiConnections")
            logs.append("[+] Wi-Fi connections enabled in lockdown service")
        except Exception:
            pass
    except Exception as e:
        return False, f"Failed to extract pairing record: {e}", logs, None

    # Save local copy
    saved_paths = []
    local_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for p in [
        os.path.join(os.getcwd(), "aircard_pairing.plist"),
        os.path.join(local_root, "aircard_pairing.plist"),
        os.path.expanduser("~/Downloads/aircard_pairing.plist")
    ]:
        try:
            with open(p, "wb") as f:
                f.write(plist_bytes)
            saved_paths.append(p)
        except Exception:
            pass

    # Step 3: Direct USB HouseArrest auto-transfer into app Documents folder
    logs.append("[*] Deploying pairing record into AmfetamineB app container...")
    pushed_via_housearrest = False
    for bid in CANDIDATE_BUNDLE_IDS:
        try:
            house_arrest = await HouseArrestService.create(lockdown, bundle_id=bid)
            root_items = await house_arrest.listdir("/")
            if "Documents" not in root_items:
                await house_arrest.makedirs("/Documents")
            
            await house_arrest.set_file_contents("/Documents/aircard_pairing.plist", plist_bytes)
            await house_arrest.set_file_contents("/Documents/airlift_pairing.plist", plist_bytes)
            logs.append(f"[+] Direct USB transfer successful for {bid}")
            pushed_via_housearrest = True
        except Exception:
            pass

    # Direct network push to AmfetamineB on iPhone (if app is running)
    synced_network = False
    for target_ip in ["127.0.0.1", "10.7.0.1"]:
        try:
            req = urllib.request.Request(
                f"http://{target_ip}:{IPHONE_SYNC_PORT}/upload_pairing",
                data=plist_bytes,
                headers={"Content-Type": "application/octet-stream"}
            )
            with urllib.request.urlopen(req, timeout=1.5) as resp:
                if resp.status == 200:
                    synced_network = True
                    logs.append(f"[+] Synced over local network to {target_ip}:{IPHONE_SYNC_PORT}")
                    break
        except Exception:
            pass

    if pushed_via_housearrest:
        msg = "Pairing record successfully transferred to AmfetamineB on iPhone."
    elif synced_network:
        msg = "Pairing record successfully synced to AmfetamineB over network."
    else:
        msg = f"Pairing record generated and saved to {saved_paths[0]}."

    return True, msg, logs, saved_paths[0] if saved_paths else None

def do_pair_device(udid=None):
    """Synchronous pairing wrapper."""
    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        ok, msg, logs, path = loop.run_until_complete(auto_pair_and_push_async(udid))
        loop.close()
        return ok, msg, logs, path
    except Exception as e:
        return False, f"Pairing error: {str(e)}", [f"Error: {e}"], None

# ---------------------------------------------------------------------------
# Clean Sleek HTML UI
# ---------------------------------------------------------------------------

HTML_UI = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AmfetamineB PC Helper</title>
    <style>
        :root {
            --bg: #0d1117;
            --card-bg: #161b22;
            --card-border: #30363d;
            --accent: #238636;
            --accent-hover: #2ea043;
            --accent-active: #196c2e;
            --text-primary: #f0f6fc;
            --text-secondary: #8b949e;
            --status-connected: #3fb950;
            --status-disconnected: #d29922;
            --status-error: #f85149;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background: var(--bg);
            color: var(--text-primary);
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            padding: 20px;
            user-select: none;
        }
        .app-window {
            width: 100%;
            max-width: 480px;
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 12px;
            padding: 24px;
            box-shadow: 0 16px 36px rgba(0,0,0,0.5);
        }
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
            padding-bottom: 12px;
            border-bottom: 1px solid var(--card-border);
        }
        .header-title {
            font-size: 18px;
            font-weight: 700;
            letter-spacing: -0.3px;
        }
        .header-version {
            font-size: 12px;
            color: var(--text-secondary);
            font-family: monospace;
            background: #21262d;
            padding: 2px 8px;
            border-radius: 6px;
        }
        .device-card {
            background: #0d1117;
            border: 1px solid var(--card-border);
            border-radius: 8px;
            padding: 16px;
            margin-bottom: 20px;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }
        .device-info {
            display: flex;
            align-items: center;
            gap: 12px;
        }
        .status-dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: var(--status-disconnected);
            transition: all 0.3s ease;
        }
        .status-dot.connected {
            background: var(--status-connected);
            box-shadow: 0 0 8px var(--status-connected);
        }
        .device-text-title {
            font-size: 14px;
            font-weight: 600;
        }
        .device-text-subtitle {
            font-size: 12px;
            color: var(--text-secondary);
            margin-top: 2px;
        }
        .btn-exploit {
            width: 100%;
            padding: 14px;
            background: var(--accent);
            color: #ffffff;
            border: none;
            border-radius: 8px;
            font-size: 15px;
            font-weight: 700;
            cursor: pointer;
            transition: background 0.15s ease, transform 0.05s ease;
            margin-bottom: 14px;
        }
        .btn-exploit:hover {
            background: var(--accent-hover);
        }
        .btn-exploit:active {
            background: var(--accent-active);
            transform: scale(0.99);
        }
        .btn-exploit:disabled {
            background: #21262d;
            color: #484f58;
            cursor: not-allowed;
            transform: none;
        }
        .result-banner {
            display: none;
            padding: 12px 14px;
            border-radius: 8px;
            font-size: 13px;
            font-weight: 500;
            margin-bottom: 16px;
            line-height: 1.4;
        }
        .result-banner.success {
            display: block;
            background: rgba(63, 185, 80, 0.12);
            border: 1px solid var(--status-connected);
            color: var(--status-connected);
        }
        .result-banner.error {
            display: block;
            background: rgba(248, 81, 73, 0.12);
            border: 1px solid var(--status-error);
            color: var(--status-error);
        }
        .log-toggle-btn {
            background: transparent;
            border: 1px solid var(--card-border);
            color: var(--text-secondary);
            font-size: 12px;
            font-weight: 600;
            padding: 8px 12px;
            border-radius: 6px;
            width: 100%;
            cursor: pointer;
            transition: all 0.2s ease;
        }
        .log-toggle-btn:hover {
            color: var(--text-primary);
            border-color: #8b949e;
        }
        .log-panel {
            display: none;
            background: #090c10;
            border: 1px solid var(--card-border);
            border-radius: 8px;
            padding: 12px;
            margin-top: 12px;
            max-height: 160px;
            overflow-y: auto;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            font-size: 11px;
            line-height: 1.5;
            color: #c9d1d9;
            white-space: pre-wrap;
            word-break: break-all;
        }
        .log-panel.open {
            display: block;
        }
    </style>
</head>
<body>
    <div class="app-window">
        <div class="header">
            <div class="header-title">AmfetamineB PC Helper</div>
            <div class="header-version">v0.1.4</div>
        </div>

        <div class="device-card">
            <div class="device-info">
                <div class="status-dot" id="statusDot"></div>
                <div>
                    <div class="device-text-title" id="deviceStatus">Searching for device...</div>
                    <div class="device-text-subtitle" id="deviceSubtitle">Connect iPhone via USB and unlock</div>
                </div>
            </div>
        </div>

        <button class="btn-exploit" id="exploitBtn" onclick="runExploit()">Exploit</button>

        <div class="result-banner" id="resultBanner"></div>

        <button class="log-toggle-btn" id="logToggleBtn" onclick="toggleLogs()">Show Logs</button>
        <div class="log-panel" id="logPanel"></div>
    </div>

    <script>
        let currentUdid = null;
        let isConnected = false;
        let isRunning = false;

        function addLog(msg) {
            const panel = document.getElementById('logPanel');
            const ts = new Date().toLocaleTimeString();
            panel.innerText += `[${ts}] ${msg}\\n`;
            panel.scrollTop = panel.scrollHeight;
        }

        function toggleLogs() {
            const panel = document.getElementById('logPanel');
            const btn = document.getElementById('logToggleBtn');
            if (panel.classList.contains('open')) {
                panel.classList.remove('open');
                btn.innerText = 'Show Logs';
            } else {
                panel.classList.add('open');
                btn.innerText = 'Hide Logs';
            }
        }

        async function pollStatus() {
            if (isRunning) return;
            try {
                const res = await fetch('/api/status');
                const data = await res.json();
                const devices = data.devices || [];

                const dot = document.getElementById('statusDot');
                const status = document.getElementById('deviceStatus');
                const subtitle = document.getElementById('deviceSubtitle');
                const btn = document.getElementById('exploitBtn');

                if (devices.length > 0) {
                    const dev = devices[0];
                    currentUdid = dev.udid;
                    isConnected = true;
                    dot.classList.add('connected');
                    status.innerText = 'Connected: ' + dev.name;
                    subtitle.innerText = 'UDID: ' + dev.udid.substring(0, 12) + '...';
                    if (!isRunning) btn.disabled = false;
                } else {
                    currentUdid = null;
                    isConnected = false;
                    dot.classList.remove('connected');
                    status.innerText = 'No device detected';
                    subtitle.innerText = 'Connect iPhone via USB and unlock';
                    if (!isRunning) btn.disabled = false; // allow attempting pair
                }
            } catch (e) {
                console.error(e);
            }
        }

        async function runExploit() {
            if (isRunning) return;
            isRunning = true;

            const btn = document.getElementById('exploitBtn');
            const banner = document.getElementById('resultBanner');
            
            btn.disabled = true;
            btn.innerText = 'Executing Exploit...';
            banner.className = 'result-banner';
            banner.style.display = 'none';

            addLog('[*] Starting exploit and pairing pipeline...');

            try {
                const res = await fetch('/api/pair', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({ udid: currentUdid })
                });
                const result = await res.json();

                if (result.logs && Array.isArray(result.logs)) {
                    for (const l of result.logs) {
                        addLog(l);
                    }
                }

                if (result.success) {
                    banner.className = 'result-banner success';
                    banner.innerText = 'Success: ' + result.message;
                    addLog('[+] Exploit completed successfully.');
                    btn.innerText = 'Exploit Completed';
                } else {
                    banner.className = 'result-banner error';
                    banner.innerText = 'Failed: ' + result.message;
                    addLog('[-] Exploit failed: ' + result.message);
                    btn.innerText = 'Retry Exploit';
                }
            } catch (e) {
                banner.className = 'result-banner error';
                banner.innerText = 'Error: ' + e.message;
                addLog('[-] Error: ' + e.message);
                btn.innerText = 'Retry Exploit';
            } finally {
                isRunning = false;
                btn.disabled = false;
            }
        }

        setInterval(pollStatus, 2000);
        pollStatus();
    </script>
</body>
</html>
"""

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

class HelperServer(BaseHTTPRequestHandler):
    def _send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        self.send_response(200)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            self.send_response(200)
            self._send_cors_headers()
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(HTML_UI.encode("utf-8"))
        elif self.path == "/api/status":
            devices = list_connected_devices()
            res = {"devices": devices}
            self.send_response(200)
            self._send_cors_headers()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(res).encode("utf-8"))
        elif self.path == "/api/download":
            target = os.path.join(os.getcwd(), "aircard_pairing.plist")
            if os.path.isfile(target):
                with open(target, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self._send_cors_headers()
                self.send_header("Content-Type", "application/x-plist")
                self.send_header("Content-Disposition", "attachment; filename=\"aircard_pairing.plist\"")
                self.end_headers()
                self.wfile.write(data)
            else:
                self.send_response(404)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/api/pair":
            try:
                length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(length) if length > 0 else b"{}"
                data = json.loads(body.decode("utf-8")) if body else {}
                udid = data.get("udid")

                success, message, logs, file_path = do_pair_device(udid)
                res = {
                    "success": success,
                    "message": message,
                    "logs": logs,
                    "file": file_path
                }
            except Exception as e:
                res = {
                    "success": False,
                    "message": f"Server error: {str(e)}",
                    "logs": [f"Server error: {e}"]
                }

            self.send_response(200)
            self._send_cors_headers()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(res).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        return

def start_server():
    server = ThreadedHTTPServer(("127.0.0.1", HTTP_PORT), HelperServer)
    server.serve_forever()

def main():
    print(f"[*] Starting AmfetamineB PC Helper on http://127.0.0.1:{HTTP_PORT} ...")
    t = threading.Thread(target=start_server, daemon=True)
    t.start()
    time.sleep(0.4)

    try:
        import webview
        print("[*] Launching GUI...")
        webview.create_window(
            "AmfetamineB PC Helper",
            f"http://127.0.0.1:{HTTP_PORT}",
            width=500,
            height=420,
            resizable=False
        )
        webview.start()
    except ImportError:
        print("[*] Opening in browser...")
        webbrowser.open(f"http://127.0.0.1:{HTTP_PORT}")
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\n[*] Exiting.")
            sys.exit(0)

if __name__ == "__main__":
    main()
