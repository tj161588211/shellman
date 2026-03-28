#!/bin/bash
# ================================================
# Ubuntu mihomo + WebUI 超级交互版（第三版优化）
# 作者：Grok（Tommy 专属定制）
# 更新：更安全配置 + 更强订阅处理 + mc 面板增强
# ================================================

set -e

echo "🚀 开始安装/优化 mihomo + WebUI（第三版）..."

if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 sudo 运行此脚本！"
    exit 1
fi

# 依赖安装
apt update -qq
apt install -y curl git jq

# 架构检测
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "❌ 不支持的架构: $ARCH"; exit 1 ;;
esac

# 选择 WebUI
echo ""
echo "=== 请选择 WebUI 面板（推荐 metacubexd） ==="
echo "1. metacubexd（官方推荐，功能丰富）"
echo "2. yacd-meta（轻量简洁）"
read -p "请输入 1 或 2（默认 1）: " UI_CHOICE
UI_CHOICE=${UI_CHOICE:-1}

if [ "$UI_CHOICE" = "1" ]; then
    UI_REPO="https://github.com/metacubex/metacubexd.git"
    UI_NAME="metacubexd"
    UI_BRANCH="gh-pages"
elif [ "$UI_CHOICE" = "2" ]; then
    UI_REPO="https://github.com/MetaCubeX/Yacd-meta.git"
    UI_NAME="yacd-meta"
    UI_BRANCH="gh-pages"
else
    UI_REPO="https://github.com/metacubex/metacubexd.git"
    UI_NAME="metacubexd"
    UI_BRANCH="gh-pages"
fi
echo "✅ 已选择: $UI_NAME"

# 下载最新 mihomo
echo "📥 获取最新 mihomo 版本..."
VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
echo "   最新版本: $VERSION"

echo "📥 下载并安装 mihomo..."
curl -L -o /tmp/mihomo.gz \
    "https://github.com/MetaCubeX/mihomo/releases/download/${VERSION}/mihomo-linux-${ARCH}-${VERSION}.gz"

gunzip -f /tmp/mihomo.gz
install -m 755 /tmp/mihomo /usr/local/bin/mihomo
echo "✅ mihomo $VERSION 已安装"

# 配置目录
CONFIG_DIR="/etc/mihomo"
mkdir -p "$CONFIG_DIR"
UI_DIR="$CONFIG_DIR/ui"

# 安装 WebUI
echo "📥 安装/更新 $UI_NAME WebUI..."
if [ -d "$UI_DIR/.git" ]; then
    git -C "$UI_DIR" pull -r --quiet || true
else
    git clone -b "$UI_BRANCH" --depth=1 "$UI_REPO" "$UI_DIR" --quiet
fi
echo "✅ $UI_NAME 已就绪"

# 交互配置
echo ""
echo "=== 端口设置 ==="
read -p "混合端口 (HTTP/HTTPS/SOCKS5) [默认 7890]: " MIXED_PORT
MIXED_PORT=${MIXED_PORT:-7890}
read -p "控制器端口 (WebUI) [默认 9090]: " CTRL_PORT
CTRL_PORT=${CTRL_PORT:-9090}

echo ""
echo "=== 面板安全 ==="
read -p "设置 WebUI 访问密钥（secret，强烈建议设置，回车跳过）: " SECRET
SECRET=${SECRET:-""}

echo ""
echo "=== 订阅链接（可选） ==="
read -p "是否现在设置订阅链接？(y/n，默认 n): " SET_SUB
if [[ "$SET_SUB" =~ ^[Yy]$ ]]; then
    read -p "请输入订阅链接（支持 Clash/Mihomo 格式）: " SUB_URL
    read -p "订阅自动更新间隔（秒，默认 3600=1小时）: " INTERVAL
    INTERVAL=${INTERVAL:-3600}
else
    SUB_URL=""
    INTERVAL=3600
fi

# 生成 config.yaml
CONFIG_FILE="$CONFIG_DIR/config.yaml"
echo "📝 生成/更新配置文件..."

cat > "$CONFIG_FILE" << EOF
# mihomo 配置（第三版优化生成）
mixed-port: $MIXED_PORT
allow-lan: true
mode: rule
log-level: info
ipv6: true
unified-delay: true
tcp-concurrent: true

external-controller: 0.0.0.0:$CTRL_PORT
external-ui: ui
secret: "$SECRET"

# DNS 推荐配置
dns:
  enable: true
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://dns.google/dns-query
    - https://cloudflare-dns.com/dns-query

# 域名嗅探
sniffer:
  enable: true
  sniffing:
    - tls
    - http

EOF

if [ -n "$SUB_URL" ]; then
    cat >> "$CONFIG_FILE" << EOF

# 订阅提供者（自动更新）
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
    # 可在 WebUI 中进一步自定义

rules:
  - MATCH,🚀 代理
EOF
    echo "✅ 已自动加入订阅配置（首次安装后会自动下载节点）"
else
    echo "✅ 已生成基础配置，后续可在 WebUI 中导入订阅"
fi

# 保存 mc 配置
cat > "$CONFIG_DIR/mc.conf" << EOF
CTRL_PORT=$CTRL_PORT
SECRET="$SECRET"
SUB_URL="$SUB_URL"
PROVIDER_NAME="default"
UI_NAME="$UI_NAME"
EOF

# systemd 服务（增加安全设置）
cat > /etc/systemd/system/mihomo.service << EOF
[Unit]
Description=mihomo (Clash Meta) Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mihomo -d $CONFIG_DIR
Restart=always
RestartSec=3
LimitNOFILE=1048576

# 安全加固
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now mihomo >/dev/null 2>&1 || true

# 创建/更新 mc 全局命令
cat > /usr/local/bin/mc << 'EOF'
#!/bin/bash
CONFIG_DIR="/etc/mihomo"
source "$CONFIG_DIR/mc.conf" 2>/dev/null || true

while true; do
    clear
    echo "========================================"
    echo "🚀 mihomo 控制面板 (mc) - 第三版"
    echo "WebUI: http://127.0.0.1:$CTRL_PORT/ui"
    echo "密钥: ${SECRET:-未设置（不安全）}"
    echo "========================================"
    echo "1. 服务状态"
    echo "2. 重启服务"
    echo "3. 停止服务"
    echo "4. 更新 mihomo 到最新版"
    echo "5. 强制更新订阅"
    echo "6. 测试配置文件"
    echo "7. 切换模式 (Global/Rule/Direct)"
    echo "8. 查看最近日志"
    echo "9. 打开 WebUI"
    echo "10. 编辑配置文件"
    echo "11. 版本信息"
    echo "0. 退出"
    echo "========================================"
    read -p "请选择操作: " choice

    case $choice in
        1) systemctl status mihomo ;;
        2) systemctl restart mihomo && echo "✅ 服务已重启" ;;
        3) systemctl stop mihomo && echo "✅ 服务已停止" ;;
        4)
            echo "📥 检查更新..."
            ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"; [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
            NEW_VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
            echo "当前: $(/usr/local/bin/mihomo --version 2>&1 | head -1)"
            echo "最新: $NEW_VERSION"
            read -p "确认更新？(y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                curl -L -o /tmp/mihomo.gz "https://github.com/MetaCubeX/mihomo/releases/download/${NEW_VERSION}/mihomo-linux-${ARCH}-${NEW_VERSION}.gz"
                gunzip -f /tmp/mihomo.gz
                install -m 755 /tmp/mihomo /usr/local/bin/mihomo
                systemctl restart mihomo
                echo "✅ mihomo 已更新到 $NEW_VERSION"
            fi
            ;;
        5)
            if [ -n "$SUB_URL" ]; then
                echo "🔄 强制更新订阅..."
                if [ -n "$SECRET" ]; then
                    curl -X PUT "http://127.0.0.1:$CTRL_PORT/providers/proxies/$PROVIDER_NAME" \
                         -H "Authorization: Bearer $SECRET" -s
                else
                    curl -X PUT "http://127.0.0.1:$CTRL_PORT/providers/proxies/$PROVIDER_NAME" -s
                fi
                echo "✅ 更新请求已发送（可在 WebUI 查看结果）"
            else
                echo "⚠️ 未配置订阅链接"
            fi
            ;;
        6) mihomo -d "$CONFIG_DIR" -t && echo "✅ 配置测试通过" || echo "❌ 配置有误" ;;
        7)
            read -p "切换到模式 (1:Global  2:Rule  3:Direct): " mode_choice
            case $mode_choice in
                1) MODE="Global" ;;
                2) MODE="Rule" ;;
                3) MODE="Direct" ;;
                *) echo "取消"; continue ;;
            esac
            if [ -n "$SECRET" ]; then
                curl -X PATCH "http://127.0.0.1:$CTRL_PORT/configs" \
                     -H "Authorization: Bearer $SECRET" \
                     -H "Content-Type: application/json" \
                     -d "{\"mode\":\"$MODE\"}" -s
            else
                curl -X PATCH "http://127.0.0.1:$CTRL_PORT/configs" \
                     -H "Content-Type: application/json" \
                     -d "{\"mode\":\"$MODE\"}" -s
            fi
            echo "✅ 已切换到 $MODE 模式"
            ;;
        8) journalctl -u mihomo -n 80 --no-pager ;;
        9)
            URL="http://127.0.0.1:$CTRL_PORT/ui"
            echo "🌐 打开 $URL"
            if command -v xdg-open > /dev/null; then xdg-open "$URL" 2>/dev/null || true; fi
            echo "如未自动打开，请手动访问: $URL"
            ;;
        10) nano "$CONFIG_DIR/config.yaml" ;;
        11)
            echo "mihomo 版本: $(/usr/local/bin/mihomo --version 2>&1 | head -1)"
            echo "WebUI: $UI_NAME"
            echo "混合端口: $MIXED_PORT"
            ;;
        0) exit 0 ;;
        *) echo "无效选项，请重试" ;;
    esac
    echo ""
    read -p "按 Enter 键返回菜单..."
done
EOF

chmod +x /usr/local/bin/mc

# 完成信息
echo ""
echo "🎉 安装/优化完成！"
echo "========================================"
echo "WebUI 地址：http://127.0.0.1:$CTRL_PORT/ui"
echo "代理地址：127.0.0.1:$MIXED_PORT （支持 HTTP/HTTPS/SOCKS5）"
echo ""
echo "🔥 强烈建议立即输入：mc"
echo "   使用 mc 控制面板进行所有日常操作（更新、切换模式、查看日志等）"
echo ""
echo "其他常用命令："
echo "   systemctl status mihomo"
echo "   sudo mihomo -d /etc/mihomo -t     # 测试配置"
echo "========================================"

sleep 2
if systemctl is-active --quiet mihomo; then
    echo "✅ mihomo 服务运行正常！"
    echo "现在输入 mc 开始使用吧～"
else
    echo "⚠️ 服务状态异常：请运行 systemctl status mihomo 查看详情"
fi
