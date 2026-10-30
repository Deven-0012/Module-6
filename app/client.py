"""Inventory client: calls the Inventory Service by its Kubernetes Service name.

It never uses Pod IPs. Every request goes to http://inventory-service:8080/items,
which cluster DNS resolves to the Service's stable ClusterIP; kube-proxy then
forwards to one of the *ready* Pods behind it.
"""
import json
import os
import time
import urllib.request
from datetime import datetime, timezone

URL = os.getenv("INVENTORY_URL", "http://inventory-service:8080/items")
INTERVAL = float(os.getenv("INTERVAL_SECONDS", "1"))


def log(msg):
    ts = datetime.now(timezone.utc).strftime("%H:%M:%S")
    print(f"[{ts}] [client] {msg}", flush=True)


if __name__ == "__main__":
    log(f"starting; target = {URL}")
    n = 0
    while True:
        n += 1
        try:
            # New connection per request (Connection: close) so each call is load-balanced.
            req = urllib.request.Request(URL, headers={"Connection": "close"})
            with urllib.request.urlopen(req, timeout=3) as resp:
                body = json.loads(resp.read())
            log(f"req #{n:<4} -> served by {body['pod']} ({body['pod_ip']}) items={len(body['items'])}")
        except Exception as exc:  # keep running through failures
            log(f"req #{n:<4} -> ERROR {exc}")
        time.sleep(INTERVAL)
