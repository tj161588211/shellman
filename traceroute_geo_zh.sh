#!/bin/bash
# traceroute_geo_zh_v3.sh
# 作者: Tong Jun & GPT-5
# 功能: 路由追踪 + IP 中文地理信息 + 延时 + 并行查询 + 缓存
# 日期: 2025-10-20

set -e

CACHE_FILE="/tmp/ipinfo_cache.txt"

# ===== 工具检查 =====
for cmd in traceroute curl jq parallel; do
    if ! command -v $cmd &>/dev/null; then
        echo "正在安装缺失依赖：$cmd ..."
        apt update -y &>/dev/null
        apt install -y $cmd &>/dev/null
    fi
done

# ===== 输入目标 =====
read -rp "请输入要追踪的目标域名或IP: " TARGET
if [[ -z "$TARGET" ]]; then
    echo "未输入目标，退出。"
    exit 1
fi
echo

# ===== 缓存查询函数 =====
lookup_ipinfo() {
    local ip="$1"
    [[ "$ip" == "*" ]] && echo "超时 | - | -" && return

    local cached
    cached=$(grep "^$ip," "$CACHE_FILE" 2>/dev/null || true)
    if [[ -n "$cached" ]]; then
        echo "${cached#*,}"
        return
    fi

    local result
    result=$(curl -s "https://ipinfo.io/${ip}/json" | jq -r '[.country, .region, .city, .org] | join(" | ")')
    if [[ -z "$result" || "$result" == "null | null | null | null" ]]; then
        result="未知 | 未知 | 未知 | 未知"
    fi
    echo "$ip,$result" >>"$CACHE_FILE"
    echo "$result"
}
export -f lookup_ipinfo  # ✅ 关键点：让 parallel 可识别

# ===== 路由追踪 =====
echo "开始追踪：$TARGET"
echo "---------------------------------------------------------------------------------------------"
echo -e "序\tIP\t\t延时(ms)\t国家\t地区\tISP"
echo "---------------------------------------------------------------------------------------------"

RAW=$(traceroute -n "$TARGET" 2>/dev/null || true)

HOPS=$(echo "$RAW" | awk '/^[ 0-9]/ {
    ip=""; time="";
    for(i=1;i<=NF;i++){
        if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) ip=$i;
        if($i ~ /^[0-9.]+ ms$/){time=$i; break}
    }
    if(ip!="") print NR" "ip" "time;
}')

# ===== 并行查询 =====
echo "$HOPS" | parallel --colsep ' ' --jobs 10 '
    hop={1}; ip={2}; delay={3};
    info=$(lookup_ipinfo "$ip")
    country=$(echo "$info" | cut -d "|" -f1 | xargs)
    region=$(echo "$info" | cut -d "|" -f2 | xargs)
    city=$(echo "$info" | cut -d "|" -f3 | xargs)
    isp=$(echo "$info" | cut -d "|" -f4 | xargs)
    printf "%-3s %-15s %-10s %-8s %-15s %-20s\n" "$hop" "$ip" "$delay" "$country" "$city" "$isp";
'

echo "---------------------------------------------------------------------------------------------"
echo "路由追踪完成！"
