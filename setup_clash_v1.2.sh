#!/bin/bash
# ================================================
# Ubuntu mihomo + WebUI 超级交互版（第四版）
# 作者：Grok（Tommy 专属定制）
# 新增：终端全局代理 + 一键完全卸载
# ================================================

set -e

echo "🚀 开始安装/优化 mihomo + WebUI（第四版）..."

if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 sudo 运行此脚本！"
    exit 1
fi

# 依赖
apt update -qq
apt install -y curl git jq

# 架构
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
else
    UI_REPO="https://github.com/MetaCubeX/Yacd-meta.git"
    UI_NAME="yacd-meta"
    UI_BRANCH="gh-pages"
fi
echo "✅ 已选择: $UI_NAME"

# 下载 mihomo
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

# WebUI
echo "📥 安装/更新 $UI_NAME WebUI..."
if [ -d "$UI_DIR/.git" ]; then
    git -C "$UI_DIR" pull -r --quiet || true
else
    git clone -b "$UI_BRANCH" --depth=1 "$UI_REPO" "$UI_DIR" --quiet
fi
echo "✅ $UI_NAME 已就绪"

# ====================== 交互配置 ======================
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
    read -p "请输入订阅链接: " SUB_URL
    read -p "订阅自动更新间隔（秒，默认 3600）: " INTERVAL
    INTERVAL=${INTERVAL:-3600}
else
    SUB_URL=""
    INTERVAL=3600
fi

echo ""
echo "=== 本地全局代理设置 ==="
read -p "是否开启终端全局代理？(y/n，默认 n): " ENABLE_GLOBAL_PROXY
GLOBAL_PROXY_ENABLED="no"
PROXY_PROTO="socks5"
if [[ "$ENABLE_GLOBAL_PROXY" =~ ^[Yy]$ ]]; then
    GLOBAL_PROXY_ENABLED="yes"
    echo "代理方式："
    echo "1. socks5（默认，推荐）"
    echo "2. http"
    read -p "请选择 (1 或 2，默认 1): " PROXY_TYPE
    PROXY_TYPE=${PROXY_TYPE:-1}
    [ "$PROXY_TYPE" = "2" ] && PROXY_PROTO="http"
    echo "✅ 将使用 $PROXY_PROTO 代理"
fi

# 原用户 home（用于全局代理）
ORIGINAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)
BASHRC="$USER_HOME/.bashrc"

# 生成 config.yaml
CONFIG_FILE="$CONFIG_DIR/config.yaml"
echo "📝 生成/更新配置文件..."
cat > "$CONFIG_FILE" << EOF
# mihomo 配置（第四版优化生成）
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

dns:
  enable: true
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://dns.google/dns-query
    - https://cloudflare-dns.com/dns-query

sniffer:
  enable: true
  sniffing:
    - tls
    - http
EOF

if [ -n "$SUB_URL" ]; then
    cat >> "$CONFIG_FILE" << EOF

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
fi

# 保存 mc 配置（含全局代理信息）
cat > "$CONFIG_DIR/mc.conf" << EOF
CTRL_PORT=$CTRL_PORT
SECRET="$SECRET"
SUB_URL="$SUB_URL"
PROVIDER_NAME="default"
UI_NAME="$UI_NAME"
GLOBAL_PROXY_ENABLED="$GLOBAL_PROXY_ENABLED"
PROXY_PROTO="$PROXY_PROTO"
ORIGINAL_USER="$ORIGINAL_USER"
MIXED_PORT=$MIXED_PORT
EOF

# 添加全局代理到 bashrc（如果开启）
if [ "$GLOBAL_PROXY_ENABLED" = "yes" ] && [ -f "$BASHRC" ]; then
    cat >> "$BASHRC" << EOF

# mihomo global proxy setup by install script
export HTTP_PROXY=${PROXY_PROTO}://127.0.0.1:$MIXED_PORT
export HTTPS_PROXY=${PROXY_PROTO}://127.0.0.1:$MIXED_PORT
export ALL_PROXY=${PROXY_PROTO}://127.0.0.1:$MIXED_PORT
export NO_PROXY="localhost,127.0.0.1,::1"
EOF
    echo "✅ 已为用户 $ORIGINAL_USER 添加全局代理到 ~/.bashrc"
    echo "   新终端自动生效，或执行：source ~/.bashrc"
fi

# systemd 服务（安全加固）
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
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now mihomo >/dev/null 2>&1 || true

# 创建/更新 mc 控制面板
cat > /usr/local/bin/mc << 'EOF'
#!/bin/bash
CONFIG_DIR="/etc/mihomo"
source "$CONFIG_DIR/mc.conf" 2>/dev/null || true

while true; do
    clear
    echo "========================================"
    echo "🚀 mihomo 控制面板 (mc) - 第四版"
    echo "WebUI: http://127.0.0.1:$CTRL_PORT/ui"
    echo "密钥: ${SECRET:-未设置}"
    echo "全局代理: ${GLOBAL_PROXY_ENABLED:-未开启}"
    echo "========================================"
    echo "1. 服务状态          2. 重启服务"
    echo "3. 停止服务          4. 更新 mihomo"
    echo "5. 强制更新订阅      6. 测试配置文件"
    echo "7. 切换模式          8. 查看日志"
    echo "9. 打开 WebUI        10. 编辑配置文件"
    echo "11. 版本信息         12. 完全卸载 mihomo"
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
                echo "✅ 已更新到 $NEW_VERSION"
            fi
            ;;
        5)
            if [ -n "$SUB_URL" ]; then
                echo "🔄 强制更新订阅..."
                if [ -n "$SECRET" ]; then
                    curl -X PUT "http://127.0.0.1:$CTRL_PORT/providers/proxies/$PROVIDER_NAME" -H "Authorization: Bearer $SECRET" -s
                else
                    curl -X PUT "http://127.0.0.1:$CTRL_PORT/providers/proxies/$PROVIDER_NAME" -s
                fi
                echo "✅ 更新请求已发送"
            else
                echo "⚠️ 未配置订阅"
            fi
            ;;
        6) mihomo -d "$CONFIG_DIR" -t && echo "✅ 配置测试通过" || echo "❌ 配置有误" ;;
        7)
            read -p "切换到模式 (1:Global  2:Rule  3:Direct): " m
            case $m in
                1) MODE="Global" ;;
                2) MODE="Rule" ;;
                3) MODE="Direct" ;;
                *) continue ;;
            esac
            if [ -n "$SECRET" ]; then
                curl -X PATCH "http://127.0.0.1:$CTRL_PORT/configs" -H "Authorization: Bearer $SECRET" -H "Content-Type: application/json" -d "{\"mode\":\"$MODE\"}" -s
            else
                curl -X PATCH "http://127.0.0.1:$CTRL_PORT/configs" -H "Content-Type: application/json" -d "{\"mode\":\"$MODE\"}" -s
            fi
            echo "✅ 已切换到 $MODE 模式"
            ;;
        8) journalctl -u mihomo -n 80 --no-pager ;;
        9)
            URL="http://127.0.0.1:$CTRL_PORT/ui"
            echo "🌐 打开 $URL"
            command -v xdg-open >/dev/null && xdg-open "$URL" 2>/dev/null || true
            ;;
        10) nano "$CONFIG_DIR/config.yaml" ;;
        11)
            echo "mihomo 版本: $(/usr/local/bin/mihomo --version 2>&1 | head -1)"
            echo "WebUI: $UI_NAME"
            echo "混合端口: $MIXED_PORT"
            ;;
        12)
            if [ "$EUID" -ne 0 ]; then
                echo "❌ 卸载需要 root 权限！请运行：sudo mc"
                read -p "按 Enter 返回..." && continue
            fi
            echo "⚠️  警告：此操作将删除所有 mihomo 相关文件、服务和配置！"
            read -p "确认卸载？(y/n): " c1
            [[ "$c1" != [Yy] ]] && continue
            read -p "再次确认（不可逆）？(y/n): " c2
            [[ "$c2" != [Yy] ]] && continue

            echo "🧹 开始完全卸载..."
            systemctl stop mihomo 2>/dev/null || true
            systemctl disable mihomo 2>/dev/null || true
            rm -f /etc/systemd/system/mihomo.service
            systemctl daemon-reload

            # 清理全局代理设置
            if [ -f "$CONFIG_DIR/mc.conf" ]; then
                source "$CONFIG_DIR/mc.conf"
                if [ "$GLOBAL_PROXY_ENABLED" = "yes" ] && [ -n "$ORIGINAL_USER" ]; then
                    USER_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)
                    BASHRC="$USER_HOME/.bashrc"
                    if [ -f "$BASHRC" ]; then
                        sed -i '/# mihomo global proxy setup by install script/,+5d' "$BASHRC" 2>/dev/null || true
                        echo "✅ 已清理 $ORIGINAL_USER 的全局代理设置"
                    fi
                fi
            fi

            rm -f /usr/local/bin/mihomo
            rm -rf /etc/mihomo
            rm -f /usr/local/bin/mc

            echo "🎉 mihomo 已完全卸载！系统已恢复干净状态。"
            echo "感谢使用，再见！"
            exit 0
            ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
    echo ""
    read -p "按 Enter 键返回菜单..."
done
EOF

chmod +x /usr/local/bin/mc

# 完成
echo ""
echo "🎉 安装/优化完成！"
echo "========================================"
echo "WebUI: http://127.0.0.1:$CTRL_PORT/ui"
echo "代理: 127.0.0.1:$MIXED_PORT"
if [ "$GLOBAL_PROXY_ENABLED" = "yes" ]; then
    echo "✅ 终端全局代理已开启（$PROXY_PROTO 协议）"
fi
echo ""
echo "🔥 立即输入：mc   ← 进入控制面板（含卸载功能）"
echo "========================================"

sleep 2
if systemctl is-active --quiet mihomo; then
    echo "✅ mihomo 服务运行正常！"
else
    echo "⚠️  服务状态异常：systemctl status mihomo"
fi
