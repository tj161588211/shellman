#!/usr/bin/env bash

############################################################
# SRS SRT Optimizer Installer
# Ubuntu 22.04 - Cross Border Stable SRT Edition
# Target: Single Stream / Stable First
############################################################

set -e

SCRIPT_VERSION="1.0.0"
INSTALL_DIR="/opt/srs"
CONFIG_DIR="${INSTALL_DIR}/conf"
DATA_DIR="${INSTALL_DIR}/data"
SERVICE_NAME="srs-srt"

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

if [[ $EUID -ne 0 ]]; then
    log_error "请使用 sudo/root 运行"
    exit 1
fi

clear

cat << "EOF"

============================================================
        SRS SRT 一键优化部署脚本
        Cross Border Stable Edition
============================================================

特性：
✓ Docker 自动安装
✓ Host 网络（最高 UDP 性能）
✓ SRT 跨国稳定优化
✓ UDP buffer 调优
✓ CPU performance 模式
✓ 网卡 Ring Buffer 优化
✓ NOTRACK（降低 UDP conntrack）
✓ 自动生成 srt.conf
✓ systemd 开机自启
✓ 自动恢复
✓ 健康检查

============================================================

EOF

sleep 2

############################################################
# BASIC CHECK
############################################################

log_step "检查系统环境"

if ! grep -q "Ubuntu" /etc/os-release; then
    log_error "当前脚本仅针对 Ubuntu 22.04 优化"
    exit 1
fi

UBUNTU_VERSION=$(lsb_release -rs)

if [[ "$UBUNTU_VERSION" != "22.04" ]]; then
    log_warn "检测到 Ubuntu ${UBUNTU_VERSION}"
    log_warn "推荐 Ubuntu 22.04"
    read -rp "是否继续？(y/N): " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 1
fi

############################################################
# USER INPUT
############################################################

echo
echo "==================== 配置向导 ===================="
echo

read -rp "请输入 SRT 监听端口 [10080]: " SRT_PORT
SRT_PORT=${SRT_PORT:-10080}

read -rp "请输入 RTMP 端口 [1935]: " RTMP_PORT
RTMP_PORT=${RTMP_PORT:-1935}

read -rp "请输入 HTTP API/FLV 端口 [8080]: " HTTP_PORT
HTTP_PORT=${HTTP_PORT:-8080}

echo
echo "跨国稳定优先推荐参数："
echo "Latency: 250ms"
echo "适用于：欧美/亚洲/跨洋公网"
echo

read -rp "SRT Latency(ms) [250]: " SRT_LATENCY
SRT_LATENCY=${SRT_LATENCY:-250}

read -rp "最大带宽 Mbps [1000]: " MAX_BW
MAX_BW=${MAX_BW:-1000}

echo
echo "启用 NOTRACK（推荐）"
echo "可降低 UDP conntrack CPU 消耗"
echo

read -rp "启用 NOTRACK? (Y/n): " ENABLE_NOTRACK
ENABLE_NOTRACK=${ENABLE_NOTRACK:-Y}

echo
echo "配置确认："
echo "SRT Port      : ${SRT_PORT}"
echo "RTMP Port     : ${RTMP_PORT}"
echo "HTTP Port     : ${HTTP_PORT}"
echo "Latency       : ${SRT_LATENCY}"
echo "Bandwidth     : ${MAX_BW} Mbps"
echo "NOTRACK       : ${ENABLE_NOTRACK}"
echo

read -rp "开始部署？(Y/n): " START_INSTALL
START_INSTALL=${START_INSTALL:-Y}

[[ "$START_INSTALL" =~ ^[Yy]$ ]] || exit 0

############################################################
# INSTALL DEPENDENCIES
############################################################

log_step "安装系统依赖"

apt-get update -y

apt-get install -y \
curl \
wget \
nano \
htop \
jq \
ca-certificates \
gnupg \
lsb-release \
software-properties-common \
apt-transport-https \
iptables \
ethtool \
cpufrequtils \
net-tools \
ufw

############################################################
# INSTALL DOCKER
############################################################

if ! command -v docker >/dev/null 2>&1; then
    log_step "安装 Docker"

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
    "deb [arch=$(dpkg --print-architecture) \
    signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

    apt-get update -y

    apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    log_info "Docker 安装完成"
else
    log_info "Docker 已安装"
fi

############################################################
# DIRECTORY
############################################################

log_step "创建目录"

mkdir -p "${CONFIG_DIR}"
mkdir -p "${DATA_DIR}"

############################################################
# CPU PERFORMANCE
############################################################

log_step "优化 CPU Governor"

if command -v cpupower >/dev/null 2>&1; then
    cpupower frequency-set -g performance || true
else
    apt-get install -y linux-tools-common linux-tools-generic
    cpupower frequency-set -g performance || true
fi

############################################################
# NETWORK INTERFACE
############################################################

log_step "检测网卡"

NIC=$(ip route | grep default | awk '{print $5}' | head -n1)

if [[ -z "$NIC" ]]; then
    log_error "无法检测网卡"
    exit 1
fi

log_info "检测到网卡: ${NIC}"

############################################################
# ETHTOOL OPTIMIZATION
############################################################

log_step "优化网卡 Ring Buffer"

ethtool -G "$NIC" rx 4096 tx 4096 || true

CPU_CORES=$(nproc)

if [[ "$CPU_CORES" -gt 4 ]]; then
    QUEUES=4
else
    QUEUES=1
fi

ethtool -L "$NIC" combined "$QUEUES" || true

############################################################
# SYSCTL OPTIMIZATION
############################################################

log_step "写入系统优化参数"

cat > /etc/sysctl.d/99-srs-srt.conf << EOF
####################################################
# SRS SRT Cross Border Optimization
####################################################

net.core.rmem_max = 33554432
net.core.wmem_max = 33554432

net.core.rmem_default = 8388608
net.core.wmem_default = 8388608

net.ipv4.udp_rmem_min = 262144
net.ipv4.udp_wmem_min = 262144

net.ipv4.udp_mem = 8388608 12582912 16777216

net.core.netdev_max_backlog = 250000
net.core.somaxconn = 65535

net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1

net.ipv4.tcp_fastopen = 3

net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

vm.min_free_kbytes = 524288
fs.file-max = 2097152
EOF

sysctl --system
############################################################
# FIREWALL
############################################################

log_step "配置防火墙"

if command -v ufw >/dev/null 2>&1; then
    ufw allow ${SRT_PORT}/udp || true
    ufw allow ${RTMP_PORT}/tcp || true
    ufw allow ${HTTP_PORT}/tcp || true
    ufw reload || true
    log_info "UFW 已放行端口"
fi

############################################################
# NOTRACK
############################################################

if [[ "$ENABLE_NOTRACK" =~ ^[Yy]$ ]]; then

    log_step "启用 UDP NOTRACK"

    mkdir -p /etc/iptables

    iptables -t raw -C PREROUTING \
    -p udp --dport ${SRT_PORT} \
    -j NOTRACK 2>/dev/null || \
    iptables -t raw -I PREROUTING \
    -p udp --dport ${SRT_PORT} \
    -j NOTRACK

    iptables -t raw -C OUTPUT \
    -p udp --sport ${SRT_PORT} \
    -j NOTRACK 2>/dev/null || \
    iptables -t raw -I OUTPUT \
    -p udp --sport ${SRT_PORT} \
    -j NOTRACK

    apt-get install -y iptables-persistent || true
    netfilter-persistent save || true

    log_info "UDP NOTRACK 已启用"
fi

############################################################
# CHECK PORT
############################################################

log_step "检查端口占用"

for port in "$SRT_PORT" "$RTMP_PORT" "$HTTP_PORT"
do
    if ss -tulnp | grep -q ":${port} "; then
        log_warn "端口 ${port} 已被占用"

        ss -tulnp | grep ":${port}"

        read -rp "继续部署？(y/N): " CONTINUE
        [[ "$CONTINUE" =~ ^[Yy]$ ]] || exit 1
    fi
done

############################################################
# GENERATE SRS CONFIG
############################################################

log_step "生成 SRS 配置"

cat > "${CONFIG_DIR}/srt.conf" << EOF
listen              ${RTMP_PORT};
max_connections     1000;
daemon              off;

http_server {
    enabled         on;
    listen          ${HTTP_PORT};
    dir             ./objs/nginx/html;
}

http_api {
    enabled         on;
    listen          1985;
}

srt_server {
    enabled         on;
    listen          ${SRT_PORT};

    maxbw           $((MAX_BW * 1000000));

    mss             1500;

    connect_timeout 8000;

    peerlatency     ${SRT_LATENCY};
    recvlatency     ${SRT_LATENCY};
    latency         ${SRT_LATENCY};
}

vhost __defaultVhost__ {

    min_latency off;
    tcp_nodelay on;

    play {
        mw_latency 100;
        gop_cache on;
        queue_length 10;
    }

    publish {
        mr off;
    }

    http_remux {
        enabled on;
        mount [vhost]/[app]/[stream].flv;
    }

    rtc {
        enabled off;
    }
}
EOF

log_info "SRS 配置已生成"

############################################################
# PULL IMAGE
############################################################

log_step "拉取 SRS 镜像"

docker pull ossrs/srs:6

############################################################
# REMOVE OLD CONTAINER
############################################################

docker rm -f srs 2>/dev/null || true

############################################################
# CREATE START SCRIPT
############################################################

log_step "创建启动脚本"

cat > ${INSTALL_DIR}/start.sh << EOF
#!/usr/bin/env bash

docker rm -f srs >/dev/null 2>&1 || true

docker run -d \
--name srs \
--restart unless-stopped \
--network host \
--ulimit nofile=1048576:1048576 \
-v ${CONFIG_DIR}/srt.conf:/usr/local/srs/conf/srt.conf \
ossrs/srs:6 \
./objs/srs -c conf/srt.conf
EOF

chmod +x ${INSTALL_DIR}/start.sh

############################################################
# SYSTEMD
############################################################

log_step "创建 systemd 服务"

cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=SRS SRT Server
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${INSTALL_DIR}/start.sh
ExecStop=/usr/bin/docker stop srs
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}

############################################################
# START SERVICE
############################################################

log_step "启动 SRS"

systemctl restart ${SERVICE_NAME}

sleep 5

############################################################
# HEALTH CHECK
############################################################

log_step "健康检查"

if docker ps | grep -q srs; then
    log_info "SRS 容器运行正常"
else
    log_error "SRS 启动失败"

    docker logs srs || true
    exit 1
fi

############################################################
# GET IP
############################################################

PUBLIC_IP=$(curl -s https://api.ipify.org || true)

if [[ -z "$PUBLIC_IP" ]]; then
    PUBLIC_IP="YOUR_SERVER_IP"
fi

clear

cat << EOF

==========================================================
            SRS SRT 部署完成
==========================================================

SRT 推流地址：

srt://${PUBLIC_IP}:${SRT_PORT}?streamid=#!::r=live/livestream,m=publish

FFmpeg 推流示例：

ffmpeg -re -i input.mp4 \
-c:v libx264 -preset veryfast -b:v 6M \
-c:a aac -b:a 192k \
-f mpegts \
"srt://${PUBLIC_IP}:${SRT_PORT}?streamid=#!::r=live/livestream,m=publish"

RTMP 拉流：

rtmp://${PUBLIC_IP}/live/livestream

HTTP-FLV：

http://${PUBLIC_IP}:${HTTP_PORT}/live/livestream.flv

WebRTC：

http://${PUBLIC_IP}:${HTTP_PORT}/players/rtc_player.html

==========================================================

服务管理：

查看状态：
systemctl status ${SERVICE_NAME}

重启：
systemctl restart ${SERVICE_NAME}

日志：
docker logs -f srs

停止：
systemctl stop ${SERVICE_NAME}

==========================================================

EOF

############################################################
# END
############################################################

log_info "安装完成"
