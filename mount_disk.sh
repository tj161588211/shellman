#!/bin/bash
# Ubuntu 22.04 数据盘管理工具（挂载 + 卸载 + 自动文件系统检测）
# Author: ChatGPT GPT-5
# Version: v4.0

echo "===== 一键挂载 / 卸载 数据盘工具 v4.0 ====="
echo

# 检查 root
if [[ $EUID -ne 0 ]]; then
  echo "❌ 请以 root 身份运行此脚本（sudo bash mount_disk.sh）"
  exit 1
fi

# 检查依赖
for cmd in lsblk parted blkid mkfs.ext4 mkfs.xfs mkfs.btrfs; do
  if ! command -v $cmd &>/dev/null; then
    echo "⚙️  缺少命令: $cmd，正在安装..."
    apt update -y && apt install -y $cmd
  fi
done

# 安装为全局命令
if [[ $0 != "/usr/local/bin/mountdisk" ]]; then
  echo "📦 正在安装脚本为全局命令：/usr/local/bin/mountdisk"
  cp "$0" /usr/local/bin/mountdisk
  chmod +x /usr/local/bin/mountdisk
  echo "✅ 现在可以直接使用命令： mountdisk"
  echo
fi

# 文件系统检测函数
detect_fs_type() {
  local DISK="$1"
  local FS=$(blkid -s TYPE -o value "$DISK" 2>/dev/null)
  if [[ -n "$FS" ]]; then
    echo "$FS"
  else
    echo "ext4"
  fi
}

# 文件系统格式化函数
format_disk() {
  local PART="$1"
  local FSTYPE="$2"
  case "$FSTYPE" in
    ext4)
      mkfs.ext4 -F "$PART"
      ;;
    xfs)
      mkfs.xfs -f "$PART"
      ;;
    btrfs)
      mkfs.btrfs -f "$PART"
      ;;
    *)
      echo "❌ 不支持的文件系统类型：$FSTYPE"
      exit 1
      ;;
  esac
}

# 菜单
echo "请选择操作模式："
echo "1) 自动挂载（自动检测文件系统并挂载 /data）"
echo "2) 手动挂载（可选择磁盘 / 文件系统 / 挂载点）"
echo "3) 卸载磁盘（安全卸载并清理 /etc/fstab）"
read -rp "请输入数字 [1-3]: " MODE
echo

######################
# 自动挂载模式
######################
if [[ $MODE == "1" ]]; then
  echo "🚀 自动挂载模式启动..."
  DISK=$(lsblk -dpno NAME,TYPE,MOUNTPOINT | awk '$2=="disk" && $3=="" {print $1}' | head -n 1)

  if [[ -z "$DISK" ]]; then
    echo "❌ 未检测到未挂载的磁盘。"
    exit 1
  fi
  echo "✅ 检测到未挂载磁盘：$DISK"

  parted -s "$DISK" mklabel gpt
  parted -s "$DISK" mkpart primary 0% 100%
  sleep 2
  PART="${DISK}1"
  echo "🔍 正在检测文件系统类型..."
  FSTYPE=$(detect_fs_type "$PART")
  echo "✅ 自动选择文件系统类型：$FSTYPE"
  format_disk "$PART" "$FSTYPE"

  MOUNT_DIR="/data"
  mkdir -p "$MOUNT_DIR"
  mount "$PART" "$MOUNT_DIR"
  echo "✅ 已挂载 $PART 到 $MOUNT_DIR"

  UUID=$(blkid -s UUID -o value "$PART")
  echo "UUID=$UUID  $MOUNT_DIR  $FSTYPE  defaults  0  2" >> /etc/fstab
  echo "✅ 已写入 /etc/fstab（开机自动挂载）"

  echo
  echo "🎉 自动挂载完成："
  lsblk -f | grep -E "NAME|$PART"
  exit 0
fi

######################
# 手动挂载模式
######################
if [[ $MODE == "2" ]]; then
  echo "🔍 可用磁盘："
  DISK_LIST=($(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}'))
  SIZE_LIST=($(lsblk -dpno NAME,SIZE,TYPE | awk '$3=="disk"{print $2}'))

  for i in "${!DISK_LIST[@]}"; do
    echo "$((i+1))) ${DISK_LIST[$i]}   (${SIZE_LIST[$i]})"
  done
  echo
  read -rp "请输入磁盘编号: " CHOICE
  if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || ((CHOICE < 1 || CHOICE > ${#DISK_LIST[@]})); then
    echo "❌ 无效选择。"
    exit 1
  fi
  DISK="${DISK_LIST[$((CHOICE-1))]}"
  echo "✅ 已选择磁盘：$DISK"

  if lsblk -no NAME "$DISK" | grep -q "${DISK}1"; then
    PART="${DISK}1"
  else
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart primary 0% 100%
    sleep 2
    PART="${DISK}1"
  fi

  echo "请选择文件系统类型："
  echo "1) ext4"
  echo "2) xfs"
  echo "3) btrfs"
  read -rp "输入数字 [1-3]: " FSTYPE_CHOICE
  case "$FSTYPE_CHOICE" in
    1) FSTYPE="ext4" ;;
    2) FSTYPE="xfs" ;;
    3) FSTYPE="btrfs" ;;
    *) echo "❌ 无效选择"; exit 1 ;;
  esac

  read -rp "是否格式化分区 $PART 为 $FSTYPE？(y/n): " CONFIRM
  if [[ $CONFIRM == "y" ]]; then
    format_disk "$PART" "$FSTYPE"
  fi

  read -rp "请输入挂载目录（例如 /data 或 /mnt/disk1）: " MOUNT_DIR
  mkdir -p "$MOUNT_DIR"
  mount "$PART" "$MOUNT_DIR"
  echo "✅ 已挂载 $PART 到 $MOUNT_DIR"

  read -rp "是否写入 /etc/fstab？(y/n): " FSTAB_CONFIRM
  if [[ $FSTAB_CONFIRM == "y" ]]; then
    UUID=$(blkid -s UUID -o value "$PART")
    echo "UUID=$UUID  $MOUNT_DIR  $FSTYPE  defaults  0  2" >> /etc/fstab
    echo "✅ 已写入 /etc/fstab"
  fi

  echo
  echo "🎉 手动挂载完成！当前状态："
  lsblk -f | grep -E "NAME|$PART"
  exit 0
fi

######################
# 卸载模式
######################
if [[ $MODE == "3" ]]; then
  echo "📦 当前挂载的磁盘："
  MOUNTED_LIST=($(lsblk -rpo NAME,MOUNTPOINT | awk '$2!="" {print $1","$2}'))

  if [[ ${#MOUNTED_LIST[@]} -eq 0 ]]; then
    echo "❌ 当前无已挂载磁盘。"
    exit 0
  fi

  for i in "${!MOUNTED_LIST[@]}"; do
    DEV=$(echo "${MOUNTED_LIST[$i]}" | cut -d',' -f1)
    DIR=$(echo "${MOUNTED_LIST[$i]}" | cut -d',' -f2)
    echo "$((i+1))) $DEV 挂载点：$DIR"
  done

  read -rp "请输入要卸载的编号: " UNMOUNT_CHOICE
  if ! [[ "$UNMOUNT_CHOICE" =~ ^[0-9]+$ ]] || ((UNMOUNT_CHOICE < 1 || UNMOUNT_CHOICE > ${#MOUNTED_LIST[@]})); then
    echo "❌ 无效选择。"
    exit 1
  fi

  TARGET_DEV=$(echo "${MOUNTED_LIST[$((UNMOUNT_CHOICE-1))]}" | cut -d',' -f1)
  TARGET_DIR=$(echo "${MOUNTED_LIST[$((UNMOUNT_CHOICE-1))]}" | cut -d',' -f2)

  umount "$TARGET_DEV" && echo "✅ 已卸载 $TARGET_DEV"

  read -rp "是否删除挂载目录 $TARGET_DIR？(y/n): " REMOVE_DIR
  [[ $REMOVE_DIR == "y" ]] && rmdir "$TARGET_DIR" 2>/dev/null && echo "✅ 已删除挂载目录"

  read -rp "是否清除 /etc/fstab 对应记录？(y/n): " REMOVE_FSTAB
  if [[ $REMOVE_FSTAB == "y" ]]; then
    UUID=$(blkid -s UUID -o value "$TARGET_DEV")
    sed -i "/$UUID/d" /etc/fstab
    echo "✅ 已从 /etc/fstab 删除记录。"
  fi

  echo
  echo "🎯 卸载完成！当前磁盘状态："
  lsblk -f
  exit 0
fi

echo "❌ 无效选择，脚本结束。"
