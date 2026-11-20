#!/bin/bash

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

post_stat() {
  curl -s -o /dev/null -X POST "{{ stats_url }}" \
    -H "X-API-Version: 1" \
    -H "X-Client-Api-key: {{ stats_api_key }}" \
    -H "Content-Type: application/json" \
    -d "{\"client_stat\":{\"stat_type\":\"$1\",\"value\":$2,\"hostname\":\"{{ hostname }}\"}}"
}

# KSTA: 1 = running newest kernel, 2/3 = newer kernel installed, reboot needed
needrestart_output=$(needrestart -b -r l)
services=$(echo "$needrestart_output" | awk '/^NEEDRESTART-SVC:/ {printf "%s\"%s\"", (n++ ? "," : ""), $2}')
kernel_status=$(echo "$needrestart_output" | awk '/^NEEDRESTART-KSTA:/ {print $2}')
if [ "${kernel_status:-0}" -gt 1 ]; then kernel=true; else kernel=false; fi

post_stat restart_needed "{\"services\":[$services],\"kernel\":$kernel}"
post_stat openssl_version "\"$(dpkg-query -W -f='${Version}' openssl)\""

if command -v nginx > /dev/null; then
  post_stat nginx_version "\"$(nginx -v 2>&1 | cut -d/ -f2)\""
fi
