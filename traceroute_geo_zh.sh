#!/usr/bin/env bash
# traceroute_geo_zh.sh（美化版，无CSV、无经纬度）

set -o pipefail
API_URL="http://ip-api.com/json"
FIELDS="status,country,regionName,city,isp,org,as"
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
    printf " %-3s │ %-18s │ %-8s │ %-26s │ %-16s │ %-24s │ %-10s\n" "$hop" "$ip" "$latency" "error" "-" "-" "-"
    return
  fi

  ok=$(echo "$resp" | jq -r '.status' 2>/dev/null || echo "fail")
  if [[ "$ok" != "success" ]]; then
    msg=$(echo "$resp" | jq -r '.message // "unknown"')
    printf " %-3s │ %-18s │ %-8s │ %-26s │ %-16s │ %-24s │ %-10s\n" "$hop" "$ip" "$latency" "$msg" "-" "-" "-"
    return
  fi

  country=$(echo "$resp" | jq -r '.country // "-"')
  region=$(echo "$resp" | jq -r '.regionName // ""')
  city=$(echo "$resp" | jq -r '.city // "-"')
  isp=$(echo "$resp" | jq -r '(.isp // "") + (if .org then " / " + .org else "" end)')
  as=$(echo "$resp" | jq -r '.as // "-"')

  [[ -n "$region" && "$region" != "" ]] && country_region="${country} / ${region}" || country_region="$country"

  printf " %-3s │ %-18s │ %-8s │ %-26s │ %-16s │ %-24s │ %-10s\n" \
    "$hop" "$ip" "$latency" "$country_region" "$city" "$isp" "$as"
}

do_traceroute() {
  local target=$1
  local max_hops=${2:-30}

  echo
  echo "🌐 开始路由追踪：$target"
  echo

  TR_OUTPUT=$(traceroute -n -m "$max_hops" "$target" 2>/dev/null)
  if [[ $? -ne 0 || -z "$TR_OUTPUT" ]]; then
    echo "traceroute 执行失败，请检查目标或网络。"
    return 1
  fi

  echo " Hop │ IP地址            │ 延迟(ms) │ 国家/省份                 │ 城市            │ ISP/组织                │ AS号"
  echo "────┼────────────────────┼──────────┼────────────────────────────┼────────────────┼──────────────────────────┼──────────────"

  echo "$TR_OUTPUT" | tail -n +2 | while IFS= read -r line; do
    hop=$(echo "$line" | awk '{print $1}')
    ip=$(echo "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
    if [[ -z "$ip" ]]; then
      ip=$(echo "$line" | grep -oE '([0-9a-fA-F:]+:+)+[0-9a-fA-F]+' | head -n1)
    fi

    latency=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\s*ms' | awk '{sum+=$1; n++} END{if(n>0) printf "%.2f", sum/n; else print "-"}')

    if [[ -z "$ip" ]]; then
      printf " %-3s │ %-18s │ %-8s │ %-26s │ %-16s │ %-24s │ %-10s\n" "$hop" "*" "-" "-" "-" "-" "-"
      continue
    fi

    resp=$(query_ip "$ip")
    format_and_print "$hop" "$ip" "$latency" "$resp"
    sleep 0.2
  done

  echo "────┴────────────────────┴──────────┴────────────────────────────┴────────────────┴──────────────────────────┴──────────────"
  echo "✅ 追踪完成：$target"
}

interactive_loop() {
  while true; do
    echo
    read -rp "请输入要 traceroute 的目标（域名或 IP），或输入 q 退出: " target
    target=${target//[[:space:]]/}
    if [[ -z "$target" ]]; then
      echo "输入为空，请重试。"
      continue
    fi
    if [[ "$target" == "q" || "$target" == "Q" ]]; then
      echo "退出。"
      break
    fi

    read -rp "最大跳数 (默认 30): " max_hops
    max_hops=${max_hops:-30}

    do_traceroute "$target" "$max_hops"
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
