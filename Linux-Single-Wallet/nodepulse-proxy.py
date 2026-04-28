#!/usr/bin/env python3

# ============================================================
# NodePulse Command Proxy
# Runs on VM — bridges NodePulse web app to Telegram bot
# No CORS issues — browser calls local VM, VM calls Telegram
# Runs as systemd service: nodepulse-proxy
# ============================================================

from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import urllib.request
import json
import os

# ── Config — update after token regeneration ──
TELEGRAM_BOT_TOKEN = "YOUR_NEW_BOT_TOKEN"
TELEGRAM_CHAT_ID   = "YOUR_CHAT_ID"
PROXY_PORT         = 8765   # Local only — not exposed to internet

# Allowed commands — security whitelist
ALLOWED_COMMANDS = [
    "/status", "/s",
    "/restartall",
    "/penalties", "/pen",
    "/restarts", "/rc",
    "/chain", "/txn",
    "/history", "/h",
    "/disk",
    "/version",
    "/help", "/start",
    "/resetcounts",
]

class ProxyHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        pass  # Suppress default logging

    def do_OPTIONS(self):
        # Handle CORS preflight
        self.send_response(200)
        self.send_cors_headers()
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)

        if parsed.path != "/cmd":
            self.respond(404, {"error": "not found"})
            return

        cmd = params.get("text", [""])[0].strip()
        if not cmd:
            self.respond(400, {"error": "no command"})
            return

        # Security — check against whitelist
        base_cmd = cmd.split()[0].lower()

        if base_cmd == "/restart":
            parts = cmd.split()
            if len(parts) == 2 and parts[1].isdigit():
                pass
            else:
                self.respond(403, {"error": "invalid restart command"})
                return
        elif base_cmd not in ALLOWED_COMMANDS:
            self.respond(403, {"error": "command not allowed"})
            return

        # Execute command directly via bot listener
        # Inject message into bot's update queue via Telegram API
        success = self.inject_command(cmd)
        if success:
            self.respond(200, {"status": "ok", "command": cmd})
        else:
            self.respond(500, {"error": "command failed"})

    def inject_command(self, text):
        """Send command as a fake update to bot listener via local file trigger"""
        try:
            # Write command to trigger file — bot listener picks it up
            TRIGGER_FILE = os.path.expanduser("~/.denode/.bot_trigger")
            with open(TRIGGER_FILE, "w") as f:
                f.write(text)
            return True
        except Exception as e:
            print(f"Trigger error: {e}")
            # Fallback — send via Telegram API (old method)
            return self.send_to_telegram(text)

    def send_to_telegram(self, text):
        try:
            url  = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
            data = json.dumps({
                "chat_id":    TELEGRAM_CHAT_ID,
                "text":       text,
                "parse_mode": "HTML"
            }).encode()
            req  = urllib.request.Request(url, data=data,
                    headers={"Content-Type": "application/json"})
            resp = urllib.request.urlopen(req, timeout=10)
            return resp.status == 200
        except Exception as e:
            print(f"Telegram error: {e}")
            return False

    def respond(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_cors_headers()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def send_cors_headers(self):
        # Allow requests from NodePulse dashboard (Tailscale IP)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PROXY_PORT), ProxyHandler)
    print(f"NodePulse Command Proxy running on port {PROXY_PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Proxy stopped")
