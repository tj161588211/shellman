#!/bin/bash
# =============================================
# 🌏 交互式路由追踪 + 中文IP地理信息显示 (Ubuntu 22.04+) V1.0
# =============================================

# 彩色输出定义
green="\e[32m"
yellow="\e[33m"
red="\e[31m"
cyan="\e[36m"
reset="\e[0m"

# 检查依赖
for cmd in curl jq traceroute ping bc; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "${yellow}检测到缺少依赖：${cmd}${reset}"
        read -rp "是否自动安装？[Y/n]: " choice
        choice=${choice:-Y}
        if [[ $choice =~ ^[Yy]$ ]]; then
            sudo apt update -y && sudo apt install -y $cmd
        else
            echo -e "${red}缺少依赖 ${cmd}，无法继续运行。${reset}"
            exit 1
        fi
    fi
done

# 交互输入目标地址
read -rp "请输入要追踪的目标域名或IP: " target
if [ -z "$target" ]; then
    echo -e "${red}错误：目标不能为空！${reset}"
    exit 1
fi

echo -e "\n${cyan}开始追踪：${target}${reset}"
echo "---------------------------------------------------------------------------------------------"
printf "${cyan}%-3s %-15s %-10s %-12s %-18s %-20s${reset}\n" "序" "IP" "延时(ms)" "国家" "地区" "ISP"
echo "---------------------------------------------------------------------------------------------"

# 执行 traceroute
hop=0
traceroute -n "$target" 2>/dev/null | while read -r line; do
    ip=$(echo "$line" | grep -oP '\b\d{1,3}(\.\d{1,3}){3}\b' | head -n1)
    if [ -z "$ip" ]; then
        continue
    fi
    hop=$((hop + 1))

    # 计算平均延时（3次ping）
    total=0
    count=0
    for i in {1..3}; do
        time=$(ping -c 1 -W 1 "$ip" 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | cut -d' ' -f1)
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

    # 查询 IP 地理信息
    info=$(curl -s "https://ipapi.co/${ip}/json/")
    country=$(echo "$info" | jq -r '.country_name // "未知"')
    region=$(echo "$info" | jq -r '.region // "未知"')
    isp=$(echo "$info" | jq -r '.org // "未知"')

    # 延时颜色判断
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
