#!/bin/bash
# ============================================================
# Ubuntu 22.04 一键安装 + 修改SSH端口工具
# 支持交互模式 / 参数模式 / 随机端口模式
# 作者: ChatGPT (GPT-5)
# ============================================================

set -e

TARGET_PATH="/usr/local/bin/change_ssh_port"
SCRIPT_TMP="/tmp/change_ssh_port_core.sh"

if [ "$EUID" -ne 0 ]; then
  echo "⚠️ 请以 root 权限运行此脚本（sudo bash $0）"
  exit 1
fi

# ==============================
# 写入核心功能脚本
# ==============================
cat > "$SCRIPT_TMP" <<'EOF'
#!/bin/bash
set -e

CONFIG_FILE="/etc/ssh/sshd_config"

usage() {
  echo "用法:"
  echo "  change_ssh_port                 # 交互模式"
  echo "  change_ssh_port -p <端口号>      # 指定端口"
  echo "  change_ssh_port -r               # 随机端口"
  exit 0
}

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请以 root 权限运行"
  exit 1
fi

# 检查 openssh-server
if ! dpkg -l | grep -q openssh-server; then
  echo "🔍 未检测到 openssh-server，正在安装..."
  apt update -y && apt install -y openssh-server
fi

# 参数解析
NEW_PORT=""
RANDOM_MODE="false"
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -p|--port) NEW_PORT="$2"; shift ;;
    -r|--random) RANDOM_MODE="true" ;;
    -h|--help) usage ;;
    *) echo "未知参数: $1"; usage ;;
  esac
  shift
done

CURRENT_PORT=$(grep -E '^Port ' "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' || echo "22")

# 随机端口函数
generate_random_port() {
  while true; do
    port=$(( ( RANDOM % 50000 ) + 15000 ))  # 15000-65000之间
    if ! ss -tuln | grep -q ":$port "; then
      echo "$port"
      return
    fi
  done
}

if [ "$RANDOM_MODE" = "true" ]; then
  NEW_PORT=$(generate_random_port)
  echo "🎲 已生成随机端口：$NEW_PORT"
elif [ -z "$NEW_PORT" ]; then
  echo "========================================="
  echo "     🚀 Ubuntu SSH端口修改工具"
  echo "========================================="
  echo "当前 SSH 端口：$CURRENT_PORT"
  echo ""
  echo "请选择操作："
  echo "1️⃣  手动输入端口"
  echo "2️⃣  随机生成端口"
  read -rp "请选择(1/2，默认1): " choice
  choice=${choice:-1}

  if [ "$choice" = "2" ]; then
    NEW_PORT=$(generate_random_port)
    echo "🎲 已生成随机端口：$NEW_PORT"
  else
    while true; do
      read -rp "请输入新的 SSH 端口号（1024–65535，默认2222）：" NEW_PORT
      NEW_PORT=${NEW_PORT:-2222}
      if [[ "$NEW_PORT" =~ ^[0-9]+$ ]] && [ "$NEW_PORT" -ge 1024 ] && [ "$NEW_PORT" -le 65535 ]; then
        break
      else
        echo "❌ 无效端口号，请重新输入。"
      fi
    done
  fi
fi

# 修改配置
if grep -q "^#*Port " "$CONFIG_FILE"; then
  sed -i "s/^#*Port .*/Port $NEW_PORT/" "$CONFIG_FILE"
else
  echo "Port $NEW_PORT" >> "$CONFIG_FILE"
fi
echo "✅ 已将 SSH 端口修改为 $NEW_PORT"

# 防火墙自动放行
if command -v ufw >/dev/null 2>&1; then
  if ufw status | grep -q "Status: active"; then
    echo "检测到 ufw 防火墙，正在放行端口..."
    ufw allow "$NEW_PORT"/tcp >/dev/null 2>&1 || true
  fi
elif command -v firewall-cmd >/dev/null 2>&1; then
  echo "检测到 firewalld，正在放行端口..."
  firewall-cmd --permanent --add-port="$NEW_PORT"/tcp >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
else
  echo "⚠️ 未检测到防火墙，跳过放行步骤。"
fi

# 重启SSH
echo "🚀 正在重启 SSH 服务..."
systemctl restart ssh || systemctl restart sshd

if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
  echo "✅ SSH 服务已成功重启"
else
  echo "⚠️ SSH 服务重启失败，请检查配置文件。"
fi

IP=$(hostname -I | awk '{print $1}')
echo ""
echo "========================================="
echo "🎯 SSH端口修改完成"
echo "📍 当前服务器IP：$IP"
echo "🔑 新端口：$NEW_PORT"
echo "💡 测试连接命令："
echo ""
echo "   ssh -p $NEW_PORT root@$IP"
echo ""
echo "✅ 修改成功，请保持当前连接直到验证新端口可用。"
echo "========================================="
EOF

# 安装脚本到系统命令
echo "📦 正在安装 SSH 修改工具到 $TARGET_PATH ..."
mv "$SCRIPT_TMP" "$TARGET_PATH"
chmod +x "$TARGET_PATH"

echo ""
echo "✅ 安装完成！现在你可以使用："
echo "-----------------------------------------"
echo "  change_ssh_port          # 交互模式"
echo "  change_ssh_port -r       # 随机端口模式"
echo "  change_ssh_port -p 2200  # 指定端口模式"
echo "-----------------------------------------"
echo ""
echo "🚀 一切就绪！"
