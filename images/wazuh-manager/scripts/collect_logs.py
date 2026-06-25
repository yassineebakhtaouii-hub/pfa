#!/usr/bin/env python3
# =============================================================================
# collect_logs.py - Suricata eve.json to Wazuh syslog forwarder
# =============================================================================
# Reads Suricata alerts from eve.json, formats as structured JSON,
# and forwards to Wazuh Manager via TCP syslog (port 1514).
# =============================================================================
import json
import socket
import time
import os
import logging
import sys

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
EVE_PATH = "/var/log/suricata/eve.json"
WAZUH_HOST = "10.0.3.10"
WAZUH_PORT = 1514
STATE_FILE = "/tmp/collect_logs.state"
POLL_INTERVAL = 5

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
log = logging.getLogger("collect_logs")

# ---------------------------------------------------------------------------
# Syslog sender
# ---------------------------------------------------------------------------
class SyslogSender:
    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.sock = None
        self._connect()

    def _connect(self):
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(10)
            self.sock.connect((self.host, self.port))
            log.info(f"Connected to Wazuh at {self.host}:{self.port}")
        except Exception as e:
            log.warning(f"Failed to connect to Wazuh: {e}")
            self.sock = None

    def send(self, message):
        if not self.sock:
            self._connect()
            if not self.sock:
                return False
        try:
            self.sock.sendall((message + "\n").encode("utf-8"))
            return True
        except Exception as e:
            log.warning(f"Send failed: {e}, reconnecting...")
            self.sock = None
            return False

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
def main():
    log.info("Suricata -> Wazuh log collector starting")
    sender = SyslogSender(WAZUH_HOST, WAZUH_PORT)

    # Track file position
    last_pos = 0
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                last_pos = int(f.read().strip())
        except (ValueError, IOError):
            last_pos = 0

    log.info(f"Starting from file position: {last_pos}")

    while True:
        try:
            if not os.path.exists(EVE_PATH):
                log.warning(f"eve.json not found at {EVE_PATH}, retrying...")
                time.sleep(POLL_INTERVAL)
                continue

            with open(EVE_PATH, "r") as f:
                f.seek(last_pos)
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    # Only forward alert events
                    if event.get("event_type") != "alert":
                        continue

                    alert = event.get("alert", {})
                    if not alert:
                        continue

                    # Build structured message for Wazuh
                    msg = {
                        "pfa_collector": "suricata",
                        "alert_timestamp": event.get("timestamp", ""),
                        "alert_signature": alert.get("signature", ""),
                        "alert_severity": alert.get("severity", 3),
                        "alert_category": alert.get("category", ""),
                        "alert_src_ip": event.get("src_ip", ""),
                        "alert_dst_ip": event.get("dest_ip", ""),
                        "alert_src_port": event.get("src_port", 0),
                        "alert_dst_port": event.get("dest_port", 0),
                        "alert_proto": event.get("proto", ""),
                    }
                    sender.send(json.dumps(msg))

                last_pos = f.tell()
                with open(STATE_FILE, "w") as sf:
                    sf.write(str(last_pos))

        except Exception as e:
            log.error(f"Error: {e}")

        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
