#!/bin/bash

echo "===== FortiSOAR Health Check ====="

echo "[1] Disk Usage"
df -h | grep -E 'vg|/var|/opt|/rabbitmq'

echo "[2] LVM Status"
vgs
lvs

echo "[3] RabbitMQ Status"
systemctl is-active rabbitmq-server
rabbitmqctl list_queues 2>/dev/null

echo "[4] Elasticsearch"
curl -s http://localhost:9200/_cluster/health?pretty

echo "[5] PostgreSQL"
systemctl is-active postgresql

echo "[6] cyops Services"
systemctl --no-pager status cyops* | grep -E "failed|active"

echo "[7] Time Sync"
timedatectl status

echo "[8] Memory"
free -m

echo "[9] Load"
uptime
