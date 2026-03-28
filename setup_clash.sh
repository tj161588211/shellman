#!/bin/bash
# ================================================
# Ubuntu 一键安装 mihomo + metacubexd 交互式脚本
# 作者：Grok（应 Tommy 要求定制）
# 支持协议：HTTP / HTTPS / SOCKS5（混合端口）
# ================================================

set -e

echo "🚀 开始安装 mihomo + metacubexd ..."

# 1. 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 sudo 运行此脚本！"
    echo "   sudo $0"
    exit 1
fi

# 2. 安装依赖
apt update -qq
apt install -y curl git

# 3. 检测架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "❌ 不支持的架构: $ARCH"; exit 1 ;;
esac
echo "✅ 检测到架构: $ARCH"

# 4. 获取最新版本
echo "📥 获取最新 mihomo 版本..."
VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
echo "   最新版本: $VERSION"

# 5. 下载并安装 mihomo
echo "📥 下载 mihomo-linux-${ARCH}-${VERSION}.gz ..."
curl -L -o /tmp/mihomo.gz \
    "https://github.com/MetaCubeX/mihomo/releases/download/${VERSION}/mihomo-linux-${ARCH}-${VERSION}.gz"

gunzip -f /tmp/mihomo.gz
mv /tmp/mihomo /usr/local/bin/mihomo
chmod +x /usr/local/bin/mihomo
echo "✅ mihomo 已安装到 /usr/local/bin/mihomo"

# 6. 创建配置目录
CONFIG_DIR="/etc/mihomo"
mkdir -p "$CONFIG_DIR"

# 7. 安装 metacubexd WebUI
UI_DIR="$CONFIG_DIR/ui"
if [ -d "$UI_DIR/.git" ]; then
    echo "🔄 更新 metacubexd WebUI..."
    git -C "$UI_DIR" pull -r --quiet || true
else
    echo "📥 首次安装 metacubexd WebUI..."
    git clone -b gh-pages --depth=1 https://github.com/metacubex/metacubexd.git "$UI_DIR" --quiet
fi
echo "✅ metacubexd 已安装到 $UI_DIR"

# 8. 交互式配置端口
echo ""
echo "=== 请设置端口（直接回车使用默认值）==="
read -p "混合端口 (HTTP/SOCKS5 共用端口) [默认 7890]: " MIXED_PORT
MIXED_PORT=${MIXED_PORT:-7890}

read -p "控制器端口 (WebUI 使用) [默认 9090]: " CTRL_PORT
CTRL_PORT=${CTRL_PORT:-9090}

# 9. 生成 config.yaml（如果不存在）
CONFIG_FILE="$CONFIG_DIR/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << EOF
# ==================== mihomo 基础配置 ====================
mixed-port: $MIXED_PORT
allow-lan: true
mode: rule
log-level: info
ipv6: true

# WebUI 配置
external-controller: 0.0.0.0:$CTRL_PORT
external-ui: ui

# 可选：如果你想以后通过 WebUI 导入订阅，这里留空即可
# proxies: []
# proxy-groups: []
# rules: []
EOF
    echo "✅ 已生成基础 config.yaml（端口已设置为你输入的值）"
else
    echo "⚠️  检测到已存在 config.yaml，跳过生成（可自行修改）"
fi

# 10. 创建 systemd 服务
SERVICE_FILE="/etc/systemd/system/mihomo.service"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=mihomo (Clash Meta) Daemon
After=network.target NetworkManager.service systemd-networkd.service

[Service]
Type=simple
ExecStart=/usr/local/bin/mihomo -d $CONFIG_DIR
Restart=always
RestartSec=3
LimitNOFILE=1048576
# 解决新版 mihomo 外部 UI 安全路径检查（ui 在工作目录内，无需额外设置）

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now mihomo >/dev/null 2>&1 || true

echo "✅ systemd 服务已创建并启动"

# 11. 完成提示
echo ""
echo "🎉 安装完成！"
echo "========================================"
echo "WebUI 地址：http://127.0.0.1:$CTRL_PORT/ui"
echo "代理地址（推荐混合端口）："
echo "   HTTP/HTTPS/SOCKS5 → 127.0.0.1:$MIXED_PORT"
echo ""
echo "使用方法："
echo "1. 浏览器打开 http://127.0.0.1:$CTRL_PORT/ui"
echo "2. 在 WebUI 左侧「配置」→ 导入你的订阅链接"
echo "3. 选择节点 → 全局/规则模式"
echo "4. 系统设置代理为 127.0.0.1:$MIXED_PORT 即可全局代理"
echo ""
echo "常用命令："
echo "   systemctl status mihomo     # 查看状态"
echo "   systemctl restart mihomo    # 重启"
echo "   sudo mihomo -d /etc/mihomo -t   # 测试配置"
echo "========================================"

# 启动状态检查
sleep 2
if systemctl is-active --quiet mihomo; then
    echo "✅ mihomo 服务正在运行！"
else
    echo "⚠️  服务启动可能有问题，请执行：systemctl status mihomo"
fi