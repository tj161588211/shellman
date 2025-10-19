#!/usr/bin/env bash
# traceroute_geo_zh.sh（精简版，无CSV，带延时信息）

set -o pipefail
API_URL="http://ip-api.com/json"
FIELDS="status,country,regionName,city,isp,org,lat,lon,query,as"
LANG_PARAM="zh-CN"

check_deps() {
  for cmd in traceroute curl jq awk sed; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "缺少依赖: $cmd"
      echo "请先安装: sudo apt update && sudo apt install -y traceroute curl jq"
      exit 3
    fi
  done
}

query_ip() {
  local ip=$1
  curl -s --max-time 8 "${API_URL}/${ip}?fields=${FIELDS}&lang=${LANG_PARAM}"
}

format_and_print() {
  local hop=$1; local ip=$2; local latency=$3; local resp="$4"

  if [[ -z "$resp" ]]; then
    printf "%-4s %-22s %-10s %-28s %-20s %-20s %-12s %s\n" "$hop" "$ip" "$latency" "error" "-" "-" "-" "-"
    return
  fi

  ok=$(echo "$resp" | jq -r '.status' 2>/dev/null || echo "fail")
  if [[ "$ok" != "success" ]]; then
    message=$(echo "$resp" | jq -r '.message // "unknown"')
    printf "%-4s %-22s %-10s %-28s %-20s %-20s %-12s %s\n" "$hop" "$ip" "$latency" "$message" "-" "-" "-" "-"
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
  [[ -n "$lat" && -n "$lon" ]] && latlon="${lat},${lon}" || latlon="-"

  printf "%-4s %-22s %-10s %-28s %-20s %-20s %-12s %s\n" "$hop" "$ip" "$latency" "$country_region" "$city" "$isp" "$latlon" "$as"
}

do_traceroute() {
  local target=$1
  local max_hops=${2:-30}

  echo "开始 traceroute -> $target (最大跳数: $max_hops)"
  TR_OUTPUT=$(traceroute -n -m "$max_hops" "$target" 2>/dev/null)
  if [[ $? -ne 0 || -z "$TR_OUTPUT" ]]; then
    echo "traceroute 执行失败，请检查目标或网络。"
    return 1
  fi

  printf "%-4s %-22s %-10s %-28s %-20s %-20s %-12s %s\n" "Hop" "IP" "延时(ms)" "国家/省份" "城市" "ISP/组织" "经纬度" "AS"
  echo "----------------------------------------------------------------------------------------------------------------------------------------------------"

  echo "$TR_OUTPUT" | tail -n +2 | while IFS= read -r line; do
    hop=$(echo "$line" | awk '{print $1}')
    ip=$(echo "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
    if [[ -z "$ip" ]]; then
      ip=$(echo "$line" | grep -oE '([0-9a-fA-F:]+:+)+[0-9a-fA-F]+' | head -n1)
    fi

    latency=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\s*ms' | awk '{sum+=$1; n++} END{if(n>0) printf "%.2f", sum/n; else print "-"}')

    if [[ -z "$ip" ]]; then
      printf "%-4s %-22s %-10s %-28s %-20s %-20s %-12s %s\n" "$hop" "*" "-" "-" "-" "-" "-" "-"
      continue
    fi

    resp=$(query_ip "$ip")
    format_and_print "$hop" "$ip" "$latency" "$resp"
    sleep 0.2
  done

  return 0
}

interactive_loop() {
  while true; do
    echo
    read -rp "请输入要 traceroute 的目标（域名或 IP），或输入 q 退出: " target
    target=${target//[[:space:]]/}
    if [[ -z "$target" ]]; then
      echo "输入为空，重试。"
      continue
    fi
    if [[ "$target" == "q" || "$target" == "Q" ]]; then
      echo "退出。"
      break
    fi

    read -rp "最大跳数 (默认 30): " max_hops
    max_hops=${max_hops:-30}

    do_traceroute "$target" "$max_hops"
    echo "完成：$target"
  done
}

# main
check_deps

if [[ -n "$1" ]]; then
  target="$1"
  do_traceroute "$target" 30
  exit 0
else
  interactive_loop
fi

exit 0
