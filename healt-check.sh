#!/bin/bash

# ===== COLORS =====
RED="\e[31m"
YELLOW="\e[33m"
GREEN="\e[32m"
BLUE="\e[36m"
NC="\e[0m"

ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
crit()  { echo -e "${RED}[CRIT]${NC}  $1"; }

echo -e "${BLUE}\n===== INFINITUM IT - FortiSOAR Configuration Health Check =====${NC}\n"

# ===== 1) DISK USAGE =====
echo -e "\n--- Disk Usage ---"

check_disk() {
    local mount="$1"
    local usage=$(df -h "$mount" 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')

    if [[ -z "$usage" ]]; then
        warn "$mount not found"
        return
    fi

    if (( usage >= 90 )); then 
        crit "$mount disk usage ${usage}% !!!"
    elif (( usage >= 80 )); then
        warn "$mount disk usage ${usage}%"
    else
        ok "$mount disk healthy (${usage}%)"
    fi
}

check_disk "/"
check_disk "/var/lib/rabbitmq"
check_disk "/var/lib/elasticsearch"
check_disk "/var/lib/pgsql"
check_disk "/var/log"
check_disk "/var/log/audit"


# ===== 2) LVM FREE SPACE =====
echo -e "\n--- LVM Free Space ---"
while read vg free; do
    free=${free%.*}
    if (( free < 5 )); then
        warn "VG '$vg' low free space (${free}G)"
    else
        ok "VG '$vg' free space OK (${free}G)"
    fi
done < <(vgs --noheadings -o vg_name,vg_free --units g | tr -d ' ')


# ===== 3) RABBITMQ STATUS =====
echo -e "\n--- RabbitMQ ---"

if systemctl is-active --quiet rabbitmq-server; then
    ok "RabbitMQ service running"
else
    crit "RabbitMQ service NOT running!"
fi

QUEUE_COUNT=$(timeout 3 rabbitmqctl list_queues 2>/dev/null | wc -l)
if [[ $? -ne 0 ]]; then
    warn "Cannot query RabbitMQ queues"
else
    ok "RabbitMQ queue count: $QUEUE_COUNT"
fi


# ===== 4) ELASTICSEARCH HEALTH =====
echo -e "\n--- Elasticsearch ---"

ES_STATUS=$(curl -s http://localhost:9200/_cluster/health | grep status | cut -d'"' -f4)

case $ES_STATUS in
    green) ok "Elasticsearch cluster green";;
    yellow) warn "Elasticsearch yellow";;
    red) crit "Elasticsearch red !!!";;
    *) warn "Elasticsearch unreachable";;
esac


# ===== 5) POSTGRESQL =====
echo -e "\n--- PostgreSQL ---"
if systemctl is-active --quiet postgresql; then
    ok "PostgreSQL running"
else
    crit "PostgreSQL NOT running!"
fi


# ===== 6) CYOPS SERVICES =====
echo -e "\n--- cyops Services ---"
FAILED=$(systemctl --no-pager --state=failed | grep cyops | wc -l)

if (( FAILED > 0 )); then
    crit "One or more cyops services FAILED!"
else
    ok "All cyops services healthy"
fi


# ===== 7) NTP & TIME =====
echo -e "\n--- Time Sync ---"
if timedatectl | grep -q "synchronized: yes"; then
    ok "Time synchronized"
else
    warn "Time NOT synchronized!"
fi


# ===== 8) MEMORY =====
echo -e "\n--- Memory ---"
MEM_FREE=$(free -m | awk '/Mem:/ {print $4}')
SWAP_USED=$(free -m | awk '/Swap:/ {print $3}')

ok "Free Memory: ${MEM_FREE}MB"
[[ $SWAP_USED -gt 0 ]] && warn "Swap in use (${SWAP_USED}MB)" || ok "Swap not used"


# ===== 9) LOAD AVERAGE =====
echo -e "\n--- Load ---"
LOAD=$(uptime | awk -F'load average:' '{print $2}')
ok "Load Average:${LOAD}"


# ===== 10) FORTINET REPO CHECK =====
echo -e "\n--- Fortinet Repo Connectivity ---"

check_url() {
    local url="$1"
    if curl -s --head --fail "$url" >/dev/null; then
        ok "Accessible: $url"
    else
        warn "Cannot reach: $url"
    fi
}

check_url "https://repo.fortisoar.fortinet.com/"
check_url "https://updates.fortinet.net/"
check_url "https://repo.fortinet.com/"

echo -e "\n${BLUE}===== Health Check Completed =====${NC}\n"
