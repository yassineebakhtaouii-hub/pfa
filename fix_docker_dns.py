#!/usr/bin/env python3
import json
config = {"data-root": "/opt/docker", "dns": ["8.8.8.8", "8.8.4.4"]}
with open("/etc/docker/daemon.json", "w") as f:
    json.dump(config, f)
print("DOCKER_DNS_CONFIGURED")
