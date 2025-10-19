#!/bin/bash
# =====================================
# 多出口 IP 信息检测脚本（延时优化版）
# 功能：检测每个公网出口 IP 的平均延时、国家、地区和 ISP
# =====================================

# 彩色输出定义
green="\e[32m"
yellow="\e[33m"
red="\e[31m"
cyan="\e[36m"
reset="\e[0m"

# 检查依赖
for cmd in curl jq ping bc; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "${red}缺少依赖：${cmd}，请先安装！${reset}"
        exit 1
    fi
done

# 打印表头
printf "\n${cyan}%-15s %-10s %-12s %-20s %-20s${reset}\n" "IP" "延时(ms)" "国家" "地区" "ISP"
echo "---------------------------------------------------------------------------------------------"

# 获取系统中所有可用的出口 IP
ip_list=$(ip addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -vE '^127|255$' | sort -u)

for ip in $ip_list; do
    # 获取公网出口 IP
    public_ip=$(curl -s --interface "$ip" https://api.ipify.org)
    if [ -z "$public_ip" ]; then
        printf "${red}%-15s %-10s %-12s %-20s %-20s${reset}\n" "$ip" "N/A" "N/A" "N/A" "N/A"
        continue
    fi

    # 平均延时计算（三次 ping）
    total=0
    count=0
    for i in {1..3}; do
        time=$(ping -c 1 -W 1 "$public_ip" 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | cut -d' ' -f1)
        if [[ $time =~ ^[0-9.]+$ ]]; then
            total=$(echo "$total + $time" | bc)
            count=$((count + 1))
        fi
    done
    if [ $count -gt 0 ]; then
        latency=$(echo "scale=1; $total / $count" | bc)
    else
        latency="N/A"
    fi

    # 获取 IP 详细信息
    ipinfo=$(curl -s "https://ipapi.co/${public_ip}/json/")
    country=$(echo "$ipinfo" | jq -r '.country_name // "未知"')
    region=$(echo "$ipinfo" | jq -r '.region // "未知"')
    isp=$(echo "$ipinfo" | jq -r '.org // "未知"')

    # 根据延时值着色
    if [[ "$latency" == "N/A" ]]; then
        color=$red
    elif (( $(echo "$latency < 100" | bc -l) )); then
        color=$green
    elif (( $(echo "$latency < 200" | bc -l) )); then
        color=$yellow
    else
        color=$red
    fi

    # 打印结果行
    printf "${cyan}%-15s${reset} ${color}%-10s${reset} %-12s %-20s %-20s\n" \
        "$public_ip" "$latency" "$country" "$region" "$isp"
done
