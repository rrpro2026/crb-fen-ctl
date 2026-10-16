#!/bin/sh

# ============================================================
# setup-systemd.sh — fanctl 一键 systemd 安装/卸载
#
# 用法：
#   sudo sh ./setup-systemd.sh         安装并启动
#   sudo sh ./setup-systemd.sh remove  停止并卸载
#
# 做的事（安装）：
#   1. 检查主脚本 crb-fen-ctl2.sh 与 ectool
#   2. ectool 没装到 /usr/local/bin 就复制过去
#   3. 按脚本实际所在路径生成 crb-fen-clt.service（不写死目录，git 克隆到哪都能用）
#   4. daemon-reload + enable --now（开机自启 + 立即运行）
#
# 卸载：disable --now（发 SIGTERM，脚本会自动恢复 EC 自动风扇控制）
#       + 删除 service 文件 + daemon-reload
# ============================================================

UNIT_NAME="crb-fen-clt"
MAIN_SCRIPT="crb-fen-ctl2.sh"
ECTOOL_SRC="ectool"
ECTOOL_DST="/usr/local/bin/ectool"

# 脚本所在目录（git 克隆到任意位置都有效）
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: root required. Run: sudo $0 [remove]"
    exit 1
fi

# 补执行位：git 检出丢 x 位、GitHub zip 下载必丢 x 位，root 顺手修复
fix_exec()
{
    if [ -f "$1" ] && [ ! -x "$1" ]; then
        chmod 755 "$1" && echo "chmod +x: ${1##*/}"
    fi
}

do_remove()
{
    systemctl disable --now "$UNIT_NAME" 2>/dev/null && echo "Stopped + disabled: $UNIT_NAME"
    # SIGTERM 已触发脚本的 EXIT trap，恢复自动风扇控制
    rm -f "/etc/systemd/system/$UNIT_NAME.service"
    systemctl daemon-reload
    echo "Removed /etc/systemd/system/$UNIT_NAME.service"
    echo "Done. EC auto fan control is restored."
}

do_install()
{
    # 0. 补执行位（git/zip 检出常丢失）
    fix_exec "$SCRIPT_DIR/setup-systemd.sh"
    fix_exec "$SCRIPT_DIR/$MAIN_SCRIPT"
    fix_exec "$SCRIPT_DIR/$ECTOOL_SRC"

    # 1. 主脚本检查
    if [ ! -f "$SCRIPT_DIR/$MAIN_SCRIPT" ]; then
        echo "Error: $MAIN_SCRIPT not found ($SCRIPT_DIR)"
        exit 1
    fi
    if [ ! -x "$SCRIPT_DIR/$MAIN_SCRIPT" ]; then
        echo "Error: $MAIN_SCRIPT not executable, run: chmod +x \"$SCRIPT_DIR/$MAIN_SCRIPT\""
        exit 1
    fi

    # 2. ectool 安装（脚本自身优先用同目录副本，但服务环境装到 PATH 更稳妥）
    if [ ! -x "$ECTOOL_DST" ]; then
        if [ -f "$SCRIPT_DIR/$ECTOOL_SRC" ]; then
            cp "$SCRIPT_DIR/$ECTOOL_SRC" "$ECTOOL_DST"
            chmod 755 "$ECTOOL_DST"
            echo "Installed: $ECTOOL_DST"
        else
            echo "Warning: $ECTOOL_SRC not in script dir, skip installing $ECTOOL_DST"
        fi
    fi

    # 3. 生成 service（ExecStart 用实际路径）
    cat > "/etc/systemd/system/$UNIT_NAME.service" <<EOF
[Unit]
Description=Fan thermal control ($MAIN_SCRIPT)
After=multi-user.target

[Service]
Type=simple
ExecStart=$SCRIPT_DIR/$MAIN_SCRIPT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    echo "Installed: /etc/systemd/system/$UNIT_NAME.service"

    # 4. 启用
    systemctl daemon-reload
    systemctl enable --now "$UNIT_NAME"
    echo ""
    echo "Done. Service is running."
    echo ""
    echo "Commands:"
    echo "  systemctl status $UNIT_NAME"
    echo "  journalctl -u $UNIT_NAME -f"
    echo "  sudo $0 remove"
}

case "${1:-install}" in
    install|add) do_install ;;
    remove|uninstall|del) do_remove ;;
    *) echo "Usage: sudo $0 [remove]"; exit 1 ;;
esac
