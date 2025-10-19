#!/bin/bash
# =============================================
# 🌏 Ubuntu 一键交互式路由追踪 + 中文地理信息显示
# ⚡ 优化版 v3.3 - 并行查询 + 翻译缓存 + ipinfo.io
# =============================================

green="\e[32m"
yellow="\e[33m"
red="\e[31m"
cyan="\e[36m"
reset="\e[0m"

for cmd in curl jq traceroute ping bc parallel; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "${yellow}检测到缺少依赖：${cmd}，正在自动安装...${reset}"
        sudo apt update -y && sudo apt install -y $cmd
    fi
done

CACHE_FILE="/tmp/ip_geo_cache.json"
[[ ! -f $CACHE_FILE ]] && echo "{}" > "$CACHE_FILE"

target=$1
if [ -z "$target" ]; then
    read -rp "请输入要追踪的目标域名或IP: " target
fi
if [ -z "$target" ]; then
    echo -e "${red}错误：目标不能为空！${reset}"
    exit 1
fi

clear
echo -e "\n${cyan}开始追踪：${target}${reset}"
echo "---------------------------------------------------------------------------------------------"
printf "${cyan}%-3s %-15s %-10s %-12s %-18s %-20s${reset}\n" "序" "IP" "延时(ms)" "国家" "地区" "ISP"
echo "---------------------------------------------------------------------------------------------"

# 🧠 获取IP地理信息（带缓存）
get_ip_info() {
    local ip="$1"
    local cache=$(jq -r --arg ip "$ip" '.[$ip]' "$CACHE_FILE")

    if [ "$cache" != "null" ]; then
        echo "$cache"
        return
    fi

    if [[ "$ip" =~ ^10\.|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-1]\.|^192\.168\. ]]; then
        echo "{\"country\":\"本地网段\",\"region\":\"-\",\"org\":\"-\"}"
        return
    fi

    local info=$(curl -s --max-time 5 "https://ipinfo.io/${ip}/json")
    if ! echo "$info" | jq empty >/dev/null 2>&1; then
        echo "{\"country\":\"未知\",\"region\":\"-\",\"org\":\"-\"}"
        return
    fi

    local country_en=$(echo "$info" | jq -r '.country // "未知"')
    local region=$(echo "$info" | jq -r '.region // ""')
    local city=$(echo "$info" | jq -r '.city // ""')
    local org=$(echo "$info" | jq -r '.org // "未知"')

    local country_cn
    cache_cn=$(jq -r --arg key "$country_en" '.[$key]' "$CACHE_FILE")
    if [ "$cache_cn" != "null" ]; then
        country_cn="$cache_cn"
    else
        country_cn=$(curl -s --max-time 5 "https://api.mymemory.translated.net/get?q=${country_en}&langpair=en|zh-CN" \
            | jq -r '.responseData.translatedText' | sed 's/\"//g')
        [[ -z "$country_cn" || "$country_cn" == "null" ]] && country_cn="$country_en"
        tmpfile=$(mktemp)
        jq --arg key "$country_en" --arg val "$country_cn" '.[$key]=$val' "$CACHE_FILE" > "$tmpfile" && mv "$tmpfile" "$CACHE_FILE"
    fi

    local result=$(jq -n --arg c "$country_cn" --arg r "$region / $city" --arg o "$org" \
        '{country:$c, region:$r, org:$o}')
    tmpfile=$(mktemp)
    jq --arg ip "$ip" --argjson val "$result" '.[$ip]=$val' "$CACHE_FILE" > "$tmpfile" && mv "$tmpfile" "$CACHE_FILE"
    echo "$result"
}

# 🛰️ 收集所有跳数 IP
ips=()
traceroute -n "$target" 2>/dev/null | while read -r line; do
    ip=$(echo "$line" | grep -oP '\b\d{1,3}(\.\d{1,3}){3}\b' | head -n1)
    [[ -z "$ip" ]] && continue
    ips+=("$ip")
done

# 并行查询所有IP地理信息
export -f get_ip_info
export CACHE_FILE
geo_info=$(printf "%s\n" "${ips[@]}" | parallel -j5 get_ip_info {})

# 输出结果
hop=0
for ip in "${ips[@]}"; do
    hop=$((hop + 1))
    info=$(echo "$geo_info" | sed -n "${hop}p")
    latency="N/A"
    total=0; count=0
    for i in {1..3}; do
        t=$(ping -c 1 -W 1 "$ip" 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | cut -d' ' -f1)
        if [[ $t =~ ^[0-9.]+$ ]]; then
            total=$(echo "$total + $t" | bc)
            count=$((count + 1))
        fi
    done
    [ $count -gt 0 ] && latency=$(echo "scale=1; $total / $count" | bc)

    country=$(echo "$info" | jq -r '.country')
    region=$(echo "$info" | jq -r '.region')
    isp=$(echo "$info" | jq -r '.org')

    if [[ "$latency" == "N/A" ]]; then
        color=$red
    elif (( $(echo "$latency < 100" | bc -l) )); then
        color=$green
    elif (( $(echo "$latency < 200" | bc -l) )); then
        color=$yellow
    else
        color=$red
    fi

    printf "%-3s %-15s ${color}%-10s${reset} %-12s %-18s %-20s\n" \
        "$hop" "$ip" "$latency" "$country" "$region" "$isp"
done

echo "---------------------------------------------------------------------------------------------"
echo -e "${cyan}路由追踪完成！${reset}"
