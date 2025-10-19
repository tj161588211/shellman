#!/usr/bin/env bash
# traceroute_geo_zh.sh
# 交互式/非交互式路由追踪并显示中文地理信息（含每跳延时）
# 用法:
#   交互式: ./traceroute_geo_zh.sh
#   非交互（单次执行并输出）: ./traceroute_geo_zh.sh example.com
#
# 依赖: traceroute curl jq awk sed bc
# Ubuntu 安装: sudo apt update && sudo apt install -y traceroute curl jq bc

set -o pipefail
API_URL="http://ip-api.com/json"
FIELDS="status,country,regionName,city,isp,org,lat,lon,query,as"
LANG_PARAM="zh-CN"

check_deps() {
  for cmd in traceroute curl jq awk sed bc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "缺少依赖: $cmd"
      echo "请先安装: sudo apt update && sudo apt install -y traceroute curl jq bc"
      exit 3
    fi
  done
}

query_ip() {
  local ip=$1
  curl -s --max-time 8 "${API_URL}/${ip}?fields=${FIELDS}&lang=${LANG_PARAM}"
}

# 提取平均 RTT（毫秒）
extract_avg_rtt() {
  local line="$1"
  avg=$(echo "$line" | grep -oE '([0-9]+\.[0-9]+|[0-9]+) ms' | sed 's/ ms$//' | awk '{s+=$1; n+=1} END{ if(n>0) printf "%.2f", s/n; else print "-"}')
  echo "$avg"
}

format_and_print() {
  local hop=$1; local ip=$2; local resp="$3"; local rtt_avg="$4"

  if [[ -z "$resp" ]]; then
    printf "%-4s %-18s %-28s %-20s %-20s %-12s %-8s %s\n" "$hop" "$ip" "error" "-" "-" "-" "-" "-"
    return
  fi

  ok=$(echo "$resp" | jq -r '.status' 2>/dev/null || echo "fail")
  if [[ "$ok" != "success" ]]; then
    message=$(echo "$resp" | jq -r '.message // empty' 2>/dev/null)
    [[ -z "$message" ]] && message="unknown"
    printf "%-4s %-18s %-28s %-20s %-20s %-12s %-8s %s\n" "$hop" "$ip" "$message" "-" "-" "-" "$rtt_avg" "-"
    return
  fi

  country=$(echo "$resp" | jq -r '.country // "-"')
  region=$(echo "$resp" | jq -r '.regionName // ""')
  city=$(echo "$resp" | jq -r '.city // "-"')
  isp=$(echo "$resp" | jq -r '(.isp // "") + (if .org then " / " + .org else "" end)')
  lat=$(echo "$resp" | jq -r '.lat // ""')
  lon=$(echo "$resp" | jq -r '.lon // ""')
  as=$(echo "$resp" | jq -r '.as // "-"')

  [[ -n "$region" && "$region" != "" ]] && country_region="${country} / ${region}" || country_region="$country"
  latlon="-"; [[ -n "$lat" && -n "$lon" ]] && latlon="${lat},${lon}"

  printf "%-4s %-18s %-28s %-20s %-20s %-12s %-8s %s\n" "$hop" "$ip" "$country_region" "$city" "$isp" "$latlon" "$rtt_avg" "$as"
}

do_traceroute() {
  local target=$1
  local max_hops=${2:-30}

  echo "开始 traceroute -> $target (最大跳数: $max_hops)"
  TR_OUTPUT=$(traceroute -n -m "$max_hops" "$target" 2>/dev/null)
  [[ $? -ne 0 || -z "$TR_OUTPUT" ]] && { echo "traceroute 执行失败，请检查网络。"; return 1; }

  printf "%-4s %-18s %-28s %-20s %-20s %-12s %-8s %s\n" "Hop" "IP" "国家/省份" "城市" "ISP/组织" "经纬度" "延时(ms)" "AS"
  echo "-----------------------------------------------------------------------------------------------------------------------------------------"

  echo "$TR_OUTPUT" | tail -n +2 | while IFS= read -r line; do
    hop=$(echo "$line" | awk '{print $1}')
    ip=$(echo "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
    [[ -z "$ip" ]] && ip=$(echo "$line" | grep -oE '([0-9a-fA-F:]+:+)+[0-9a-fA-F]+' | head -n1)
    rtt_avg=$(extract_avg_rtt "$line")

    if [[ -z "$ip" ]]; then
      printf "%-4s %-18s %-28s %-20s %-20s %-12s %-8s %s\n" "$hop" "*" "-" "-" "-" "-" "$rtt_avg" "-"
      continue
    fi

    resp=$(query_ip "$ip")
    format_and_print "$hop" "$ip" "$resp" "$rtt_avg"
    sleep 0.2
  done
}

interactive_loop() {
  while true; do
    echo
    read -rp "请输入要 traceroute 的目标（域名或 IP），或输入 q 退出: " target
    target=${target//[[:space:]]/}
    [[ -z "$target" ]] && { echo "输入为空，请重试。"; continue; }
    [[ "$target" =~ ^[qQ]$ ]] && { echo "退出。"; break; }

    read -rp "最大跳数 (默认 30): " max_hops
    max_hops=${max_hops:-30}

    do_traceroute "$target" "$max_hops"
    echo "完成：$target"
  done
}

check_deps

if [[ -n "$1" ]]; then
  do_traceroute "$1" 30
else
  interactive_loop
fi

exit 0
