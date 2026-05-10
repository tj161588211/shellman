#!/usr/bin/env bash

set -e

GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

log(){ echo -e "${GREEN}[INFO]${NC} $1"; }
err(){ echo -e "${RED}[ERR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
  err "请用 root 运行"
  exit 1
fi

clear
echo "================================================="
echo "     SRS CDN Pro SRT System Installer"
echo "================================================="

########################################################
# INPUT
########################################################

read -rp "SRT端口 [10080]: " SRT_PORT
SRT_PORT=${SRT_PORT:-10080}

read -rp "HTTP端口 [8080]: " HTTP_PORT
HTTP_PORT=${HTTP_PORT:-8080}

read -rp "RTMP端口 [1935]: " RTMP_PORT
RTMP_PORT=${RTMP_PORT:-1935}

read -rp "跨国延迟(ms) [300]: " LAT
LAT=${LAT:-300}

########################################################
# SYSTEM OPTIMIZATION
########################################################

log "系统网络优化"

cat > /etc/sysctl.d/99-srs-cdn.conf <<EOF
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 500000
net.core.somaxconn = 65535

net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

net.ipv4.udp_mem = 16777216 33554432 67108864
vm.min_free_kbytes = 1048576
EOF

sysctl --system

########################################################
# CPU
########################################################

log "CPU performance mode"

if command -v cpupower >/dev/null; then
  cpupower frequency-set -g performance || true
fi

########################################################
# DOCKER CHECK (IMPORTANT)
########################################################

log "检查 Docker"

if ! command -v docker >/dev/null; then
  log "安装 Docker"

  curl -fsSL https://get.docker.com | bash
  systemctl enable docker
  systemctl start docker
fi

########################################################
# CLEAN OLD
########################################################

docker rm -f srs >/dev/null 2>&1 || true

########################################################
# CONFIG
########################################################

mkdir -p /opt/srs/conf

cat > /opt/srs/conf/srt.conf <<EOF
listen ${RTMP_PORT};

http_server {
    enabled on;
    listen ${HTTP_PORT};
}

srt_server {
    enabled on;
    listen ${SRT_PORT};

    latency ${LAT};
    peerlatency ${LAT};
    recvlatency ${LAT};

    maxbw 1000000000;
}

vhost __defaultVhost__ {
    tcp_nodelay on;
    min_latency off;

    play {
        gop_cache on;
        queue_length 15;
    }

    rtc {
        enabled off;
    }
}
EOF

########################################################
# START SCRIPT
########################################################

cat > /opt/srs/start.sh <<EOF
#!/usr/bin/env bash

docker rm -f srs >/dev/null 2>&1 || true

docker run -d \
--name srs \
--restart unless-stopped \
--network host \
--ulimit nofile=1048576:1048576 \
-v /opt/srs/conf/srt.conf:/usr/local/srs/conf/srt.conf \
ossrs/srs:6 \
./objs/srs -c conf/srt.conf
EOF

chmod +x /opt/srs/start.sh

########################################################
# SYSTEMD
########################################################

cat > /etc/systemd/system/srs-cdn.service <<EOF
[Unit]
Description=SRS CDN Pro
After=network-online.target docker.service

[Service]
ExecStart=/bin/bash /opt/srs/start.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable srs-cdn
systemctl restart srs-cdn

########################################################
# DONE
########################################################

IP=$(curl -s ifconfig.me || echo "YOUR_IP")

echo ""
echo "================ DEPLOY DONE ================"
echo "SRT Push:"
echo "srt://${IP}:${SRT_PORT}?streamid=live/stream"
echo ""
echo "RTMP:"
echo "rtmp://${IP}/live/stream"
echo "============================================="
