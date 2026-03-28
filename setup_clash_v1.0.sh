#!/bin/bash
# ================================================
# Ubuntu 一键安装 mihomo + WebUI（metacubexd / yacd-meta）超级交互版
# 作者：Grok（应 Tommy 要求二版定制）
# 支持：HTTP/HTTPS/SOCKS5 + 订阅自动转换 + mc 控制面板
# ================================================

set -e

echo "🚀 开始安装 mihomo + WebUI 超级交互版 ..."

# 1. 检查 root
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 sudo 运行！"
    exit 1
fi

# 2. 安装依赖
apt update -qq
apt install -y curl git

# 3. 检测架构
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "❌ 不支持架构: $ARCH"; exit 1 ;;
esac
echo "✅ 检测到架构: $ARCH"

# 4. 选择 WebUI 面板
echo ""
echo "=== 请选择 WebUI 面板 ==="
echo "1. metacubexd（官方推荐，功能最全）"
echo "2. yacd-meta（轻量经典）"
read -p "请输入 1 或 2（默认 1）: " UI_CHOICE
UI_CHOICE=${UI_CHOICE:-1}
if [ "$UI_CHOICE" = "1" ]; then
    UI_REPO="https://github.com/metacubex/metacubexd.git"
    UI_NAME="metacubexd"
elif [ "$UI_CHOICE" = "2" ]; then
    UI_REPO="https://github.com/MetaCubeX/Yacd-meta.git"
    UI_NAME="yacd-meta"
else
    UI_REPO="https://github.com/metacubex/metacubexd.git"
    UI_NAME="metacubexd"
fi
echo "✅ 已选择: $UI_NAME"

# 5. 获取最新 mihomo 版本
echo "📥 获取最新 mihomo 版本..."
VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
echo "   最新版本: $VERSION"

# 6. 下载安装 mihomo
echo "📥 下载 mihomo-linux-${ARCH}-${VERSION}.gz ..."
curl -L -o /tmp/mihomo.gz \
    "https://github.com/MetaCubeX/mihomo/releases/download/${VERSION}/mihomo-linux-${ARCH}-${VERSION}.gz"

gunzip -f /tmp/mihomo.gz
mv /tmp/mihomo /usr/local/bin/mihomo
chmod +x /usr/local/bin/mihomo
echo "✅ mihomo 已安装"

# 7. 配置目录
CONFIG_DIR="/etc/mihomo"
mkdir -p "$CONFIG_DIR"
UI_DIR="$CONFIG_DIR/ui"

# 8. 安装/更新 WebUI
if [ -d "$UI_DIR/.git" ]; then
    echo "🔄 更新 $UI_NAME WebUI..."
    git -C "$UI_DIR" pull -r --quiet || true
else
    echo "📥 安装 $UI_NAME WebUI..."
    git clone -b gh-pages --depth=1 "$UI_REPO" "$UI_DIR" --quiet
fi
echo "✅ $UI_NAME 已安装到 $UI_DIR"

# 9. 交互式配置
echo ""
echo "=== 端口设置 ==="
read -p "混合端口 (HTTP/SOCKS5) [默认 7890]: " MIXED_PORT
MIXED_PORT=${MIXED_PORT:-7890}
read -p "控制器端口 (WebUI) [默认 9090]: " CTRL_PORT
CTRL_PORT=${CTRL_PORT:-9090}

echo ""
echo "=== 面板密钥 ==="
read -p "设置 WebUI 访问密钥（secret，回车为空）: " SECRET
SECRET=${SECRET:-""}

echo ""
echo "=== 订阅设置 ==="
read -p "是否设置节点订阅链接？(y/n，默认 n): " SET_SUB
if [[ "$SET_SUB" =~ ^[Yy]$ ]]; then
    read -p "请输入订阅链接: " SUB_URL
    read -p "自动更新间隔（秒，默认 3600=1小时）: " INTERVAL
    INTERVAL=${INTERVAL:-3600}
else
    SUB_URL=""
    INTERVAL=3600
fi

# 10. 生成/更新 config.yaml
CONFIG_FILE="$CONFIG_DIR/config.yaml"
if [ -f "$CONFIG_FILE" ]; then
    read -p "⚠️  已存在 config.yaml，是否重新配置？(y/n，默认 n): " RECONFIG
    if [[ ! "$RECONFIG" =~ ^[Yy]$ ]]; then
        echo "✅ 保留原有配置"
        SUB_URL=""  # 避免覆盖
    fi
fi

if [ ! -f "$CONFIG_FILE" ] || [[ "$RECONFIG" =~ ^[Yy]$ ]]; then
    cat > "$CONFIG_FILE" << EOF
# ==================== mihomo 配置（由安装脚本生成） ====================
mixed-port: $MIXED_PORT
allow-lan: true
mode: rule
log-level: info
ipv6: true

external-controller: 0.0.0.0:$CTRL_PORT
external-ui: ui
secret: "$SECRET"

EOF

    if [ -n "$SUB_URL" ]; then
        cat >> "$CONFIG_FILE" << EOF

# ==================== 订阅配置 ====================
proxy-providers:
  default:
    type: http
    url: "$SUB_URL"
    interval: $INTERVAL
    health-check:
      enable: true
      url: http://www.gstatic.com/generate_204
      interval: 300

proxy-groups:
  - name: "🚀 代理"
    type: select
    use:
      - default

rules:
  - MATCH,🚀 代理
EOF
        echo "✅ 已自动生成订阅配置（自动更新每 $INTERVAL 秒）"
    else
        echo "✅ 已生成基础配置（可后期在 WebUI 导入订阅）"
    fi
fi

# 11. 保存 mc 控制面板配置文件
cat > "$CONFIG_DIR/mc.conf" << EOF
CTRL_PORT=$CTRL_PORT
SECRET="$SECRET"
SUB_URL="$SUB_URL"
PROVIDER_NAME="default"
UI_NAME="$UI_NAME"
EOF

# 12. 创建 systemd 服务
SERVICE_FILE="/etc/systemd/system/mihomo.service"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=mihomo (Clash Meta) Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mihomo -d $CONFIG_DIR
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now mihomo >/dev/null 2>&1

echo "✅ systemd 服务已启用"

# 13. 创建全局 mc 控制面板命令
cat > /usr/local/bin/mc << 'EOF'
#!/bin/bash
# mihomo 控制面板 - Tommy 专属
CONFIG_DIR="/etc/mihomo"
source "$CONFIG_DIR/mc.conf" 2>/dev/null || true

while true; do
    clear
    echo "========================================"
    echo "🚀 mihomo 控制面板 (mc)"
    echo "WebUI: http://127.0.0.1:$CTRL_PORT/ui"
    echo "密钥: ${SECRET:-无}"
    echo "========================================"
    echo "1. 查看服务状态"
    echo "2. 重启服务"
    echo "3. 停止服务"
    echo "4. 更新 mihomo 到最新版"
    echo "5. 强制更新订阅"
    echo "6. 查看最近日志"
    echo "7. 打开 WebUI（浏览器）"
    echo "8. 编辑配置文件"
    echo "9. 版本信息"
    echo "0. 退出"
    echo "========================================"
    read -p "请输入选项: " choice

    case $choice in
        1) systemctl status mihomo ;;
        2) systemctl restart mihomo && echo "✅ 已重启" ;;
        3) systemctl stop mihomo && echo "✅ 已停止" ;;
        4)
            echo "📥 更新 mihomo..."
            ARCH=$(uname -m); [ "$ARCH" = "x86_64" ] && ARCH="amd64"; [ "$ARCH" = "aarch64" ] && ARCH="arm64"
            VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            curl -L -o /tmp/mihomo.gz "https://github.com/MetaCubeX/mihomo/releases/download/${VERSION}/mihomo-linux-${ARCH}-${VERSION}.gz"
            gunzip -f /tmp/mihomo.gz
            mv /tmp/mihomo /usr/local/bin/mihomo
            chmod +x /usr/local/bin/mihomo
            systemctl restart mihomo
            echo "✅ 更新完成！当前版本: $VERSION"
            ;;
        5)
            if [ -n "$SUB_URL" ]; then
                echo "🔄 强制更新订阅..."
                if [ -n "$SECRET" ]; then
                    curl -X PUT "http://127.0.0.1:$CTRL_PORT/providers/proxies/$PROVIDER_NAME" \
                         -H "Authorization: Bearer $SECRET" --silent
                else
                    curl -X PUT "http://127.0.0.1:$CTRL_PORT/providers/proxies/$PROVIDER_NAME" --silent
                fi
                echo "✅ 订阅更新请求已发送"
            else
                echo "⚠️ 未设置订阅链接"
            fi
            ;;
        6) journalctl -u mihomo -n 100 --no-pager ;;
        7)
            URL="http://127.0.0.1:$CTRL_PORT/ui"
            echo "🌐 正在打开 $URL"
            if command -v xdg-open >/dev/null; then
                xdg-open "$URL" 2>/dev/null || echo "请手动打开: $URL"
            else
                echo "请在浏览器打开: $URL"
            fi
            ;;
        8) nano "$CONFIG_DIR/config.yaml" ;;
        9)
            echo "mihomo 版本: $(/usr/local/bin/mihomo --version 2>&1 | head -1)"
            echo "WebUI: $UI_NAME"
            ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
    echo ""
    read -p "按 Enter 键继续..."
done
EOF

chmod +x /usr/local/bin/mc
echo "✅ 已创建全局命令 mc（随时输入 mc 调出控制面板）"

# 14. 完成
echo ""
echo "🎉 安装完成！"
echo "========================================"
echo "WebUI 地址：http://127.0.0.1:$CTRL_PORT/ui"
echo "混合代理地址：127.0.0.1:$MIXED_PORT （HTTP/HTTPS/SOCKS5）"
echo ""
echo "🔥 现在输入命令：mc   ← 进入超级控制面板"
echo "常用命令："
echo "   mc                  # 控制面板"
echo "   systemctl status mihomo"
echo "   sudo mihomo -d /etc/mihomo -t   # 测试配置"
echo "========================================"

sleep 2
if systemctl is-active --quiet mihomo; then
    echo "✅ mihomo 服务正在运行！"
    echo "🎉 直接输入 mc 开始使用吧！"
else
    echo "⚠️  服务可能有问题：systemctl status mihomo"
fi