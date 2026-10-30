"""Inventory Service: a tiny HTTP API that reports which Pod served each request.

Endpoints
  GET /items    -> inventory list + the Pod name/IP that answered
  GET /healthz  -> liveness  (always 200 while the process is up)
  GET /ready    -> readiness (503 while /tmp/not-ready exists, else 200)

Readiness can be toggled from outside the Pod without restarting it:
  kubectl exec <pod> -- touch /tmp/not-ready   # fail readiness
  kubectl exec <pod> -- rm /tmp/not-ready      # restore readiness
"""
import json
import os
import signal
import socket
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.getenv("PORT", "8080"))
POD_NAME = os.getenv("POD_NAME", socket.gethostname())
POD_IP = os.getenv("POD_IP", "unknown")
NOT_READY_FILE = os.getenv("NOT_READY_FILE", "/tmp/not-ready")

INVENTORY = [
    {"item_id": "ITEM-001", "name": "keyboard", "stock": 42},
    {"item_id": "ITEM-002", "name": "mouse", "stock": 17},
    {"item_id": "ITEM-003", "name": "monitor", "stock": 8},
]


def log(msg):
    ts = datetime.now(timezone.utc).strftime("%H:%M:%S")
    print(f"[{ts}] [{POD_NAME}] {msg}", flush=True)


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/healthz":
            self._send(200, {"status": "alive"})
        elif self.path == "/ready":
            if os.path.exists(NOT_READY_FILE):
                self._send(503, {"status": "not-ready", "pod": POD_NAME})
            else:
                self._send(200, {"status": "ready", "pod": POD_NAME})
        elif self.path == "/items":
            log(f"served /items to {self.client_address[0]}")
            self._send(200, {"pod": POD_NAME, "pod_ip": POD_IP, "items": INVENTORY})
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, *args):  # silence default per-request logging (probes are noisy)
        pass


def shutdown(signum, frame):
    # Kubernetes sends SIGTERM on Pod deletion; exit promptly instead of waiting
    # for the 30s grace period to expire and the kubelet to SIGKILL us.
    log("SIGTERM received, shutting down")
    sys.exit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, shutdown)
    log(f"inventory service listening on :{PORT}")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
