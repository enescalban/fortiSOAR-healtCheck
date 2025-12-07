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


# ======================================================================
# 1) DISK USAGE
# ======================================================================
echo -e "\n--- Disk Usage ---"

check_disk() {
    local mount="$1"
    local usage

    usage=$(df -h "$mount" 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')

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


# ======================================================================
# 2) LVM FREE SPACE
# ======================================================================
echo -e "\n--- LVM Free Space ---"

# vgs çıktısını okuyup her VG için boş alanı kontrol ediyoruz
while read -r vg free; do
    # Örnek: "<24.00g" / "9.76g" gibi değerleri temizle -> sadece tam sayı kalsın
    free=$(echo "$free" | sed 's/[^0-9.]//g' | cut -d'.' -f1)

    if [[ -z "$free" ]]; then
        warn "VG '$vg' free space could not be detected"
        continue
    fi

    if (( free < 5 )); then
        warn "VG '$vg' low free space (${free}G)"
    else
        ok "VG '$vg' free space OK (${free}G)"
    fi
done < <(vgs --noheadings -o vg_name,vg_free --units g 2>/dev/null | tr -s ' ' | sed 's/^ //')


# ======================================================================
# 3) RABBITMQ STATUS
# ======================================================================
echo -e "\n--- RabbitMQ ---"

if systemctl is-active --quiet rabbitmq-server 2>/dev/null; then
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


# ======================================================================
# 4) ELASTICSEARCH HEALTH
# ======================================================================
echo -e "\n--- Elasticsearch ---"

ES_STATUS=$(curl -s http://localhost:9200/_cluster/health 2>/dev/null | grep status | cut -d'"' -f4)

case $ES_STATUS in
    green)  ok   "Elasticsearch cluster green" ;;
    yellow) warn "Elasticsearch yellow" ;;
    red)    crit "Elasticsearch red !!!" ;;
    *)      warn "Elasticsearch unreachable" ;;
esac


# ======================================================================
# 5) POSTGRESQL
# ======================================================================
echo -e "\n--- PostgreSQL ---"

if systemctl is-active --quiet postgresql 2>/dev/null; then
    ok "PostgreSQL running"
else
    crit "PostgreSQL NOT running!"
fi


# ======================================================================
# 6) CYOPS SERVICES (GENEL DURUM)
# ======================================================================
echo -e "\n--- CyOps Services (General) ---"

FAILED_CYOPS=$(systemctl --no-pager --state=failed 2>/dev/null | grep -c cyops || true)

if (( FAILED_CYOPS > 0 )); then
    crit "One or more cyops services FAILED (count: $FAILED_CYOPS)"
else
    ok "No cyops services in failed state"
fi


# ======================================================================
# 6.1) CYOPS MICRO-SERVICES (DETAYLI)
# ======================================================================
echo -e "\n--- CyOps Microservices (Detailed) ---"

check_service() {
    local svc="$1"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        ok "$svc running"
    else
        crit "$svc NOT running!"
    fi
}

# Buradaki isimler ortamına göre değişebilir; olmayan servisler için WARN veriyoruz
SERVICES=(
    "cyops-engine"
    "cyops-frontend"
    "cyops-worker"
    "cyops-database"
    "cyops-rabbitmq"
)

for svc in "${SERVICES[@]}"; do
    if systemctl list-units --type=service 2>/dev/null | grep -q "$svc"; then
        check_service "$svc"
    else
        warn "$svc service not found on system"
    fi
done


# ======================================================================
# 7) NTP & TIME
# ======================================================================
echo -e "\n--- Time Sync ---"

if timedatectl 2>/dev/null | grep -q "System clock synchronized: yes"; then
    ok "Time synchronized"
else
    warn "Time NOT synchronized!"
fi


# ======================================================================
# 8) MEMORY
# ======================================================================
echo -e "\n--- Memory ---"

MEM_FREE=$(free -m | awk '/Mem:/ {print $4}')
SWAP_USED=$(free -m | awk '/Swap:/ {print $3}')

ok "Free Memory: ${MEM_FREE}MB"
if [[ "$SWAP_USED" -gt 0 ]]; then
    warn "Swap in use (${SWAP_USED}MB)"
else
    ok "Swap not used"
fi


# ======================================================================
# 9) LOAD AVERAGE
# ======================================================================
echo -e "\n--- Load ---"

LOAD=$(uptime | awk -F'load average:' '{gsub(/^[ \t]+/,"",$2); print $2}')
ok "Load Average: ${LOAD}"


# ======================================================================
# 10) FORTISOAR / REPO / CONTENTHUB CONNECTIVITY
# ======================================================================
echo -e "\n--- FortiSOAR / Repo / ContentHub Connectivity ---"

check_url() {
    local url="$1"
    if curl -s --head --fail "$url" >/dev/null 2>&1; then
        ok "Accessible: $url"
    else
        warn "Cannot reach: $url"
    fi
}

# FortiSOAR için kritik endpoint'ler
check_url "https://repo.fortisoar.fortinet.com/"
check_url "https://globalupdate.fortinet.net/"
check_url "https://fortisoar.contenthub.fortinet.com/"
check_url "https://pypi.python.org/"
check_url "https://mirrors.rockylinux.org/"
check_url "https://www.ntppool.org/"

echo -e "\n${BLUE}===== Health Check Completed =====${NC}\n"
