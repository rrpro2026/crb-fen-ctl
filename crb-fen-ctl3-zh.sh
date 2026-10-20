#!/bin/sh

# ============================================================
# crb-fen-ctl3-zh.sh — Chromebox 风扇温控 v3（中文输出版，RRPRO by 20261018）
#
# = v2 中文版 + 升档温度滤波：
#   连续 UP_N 轮达到升档阈值才升档（默认 2 轮 ≈ 10 秒），
#   吸收后台任务瞬时尖峰，避免风扇"瞬时尖叫"；代价是升档慢一轮。
#   紧急温度 EMERG（默认 90°C）绕过滤波立即升档，保底安全。
#   UP_N=1 即回到不滤波行为。
#
# 配置集中在下方配置区，支持环境变量覆盖：
#   sudo INTERVAL=10 UP1=50 ./crb-fen-ctl3-zh.sh
#
# 日志：静默，只在变档时输出一行（无时间戳，journalctl 自带）：
#   56C -> 2800RPM | PWR 8.3W | USE 12%
# 启动 / 退出各一行
# 功耗用 RAPL energy_uj 差分，CPU% 用 /proc/stat 差分（都不阻塞）
# 退出时恢复自动风扇控制
#
# 档位规则：达到升档阈值升入下一档；降到阈值以下 HYST 才降档
#   < 45°C  → 1500 RPM      65-75°C → 3800 RPM
#   45-55°C → 2000 RPM      75-80°C → 4500 RPM
#   55-65°C → 2800 RPM      >= 80°C → 5600 RPM（满速）
# ============================================================

# ---------------- 配置区（要改就改这里） ----------------
# ectool 路径，留空自动探测：脚本同目录 → /usr/local/bin
ECTOOL="${ECTOOL:-}"

# 检测间隔（秒）
INTERVAL="${INTERVAL:-5}"

# 回差（°C）：降档要比升档阈值低这么多
HYST="${HYST:-5}"

# 升档滤波：连续 UP_N 轮达到升档阈值才升档（1=不滤波，同 v2）
UP_N="${UP_N:-2}"

# 紧急温度（°C）：达到则绕过滤波立即升档，保底安全
EMERG="${EMERG:-90}"

# 单行状态文件，留空不写（每轮覆盖，恒 1 行）
STATUS_FILE="${STATUS_FILE:-}"

# 启动档位（1-6）
INIT_LVL="${INIT_LVL:-2}"

# 升档阈值（°C）：达到该温度升入下一档
UP1="${UP1:-45}"    # 1档 → 2档
UP2="${UP2:-55}"    # 2档 → 3档
UP3="${UP3:-65}"    # 3档 → 4档
UP4="${UP4:-75}"    # 4档 → 5档
UP5="${UP5:-80}"    # 5档 → 6档

# 各档目标转速（RPM）
RPM1="${RPM1:-1500}"
RPM2="${RPM2:-2000}"
RPM3="${RPM3:-2800}"
RPM4="${RPM4:-3800}"
RPM5="${RPM5:-4500}"
RPM6="${RPM6:-5600}"
# ----------------------------------------------------------

# ectool 自动探测（配置区 ECTOOL 留空时生效）
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# 补执行位：git 检出/zip 下载常丢失 x 位（非 root 时静默失败，走下面回退）
if [ -f "$SCRIPT_DIR/ectool" ] && [ ! -x "$SCRIPT_DIR/ectool" ]; then
    chmod 755 "$SCRIPT_DIR/ectool" 2>/dev/null
fi
if [ -z "$ECTOOL" ]; then
    if [ -x "$SCRIPT_DIR/ectool" ]; then
        ECTOOL="$SCRIPT_DIR/ectool"
    else
        ECTOOL="/usr/local/bin/ectool"
    fi
fi

# 需要 root 才能访问 /dev/cros_ec
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：需要 root 权限。请运行：sudo $0"
    exit 1
fi

if [ ! -x "$ECTOOL" ]; then
    echo "错误：未找到 ectool（$ECTOOL）"
    exit 1
fi

# 启动时一次性定位 sysfs 路径（循环内不再 glob/cat name）
TEMP_FILE=""
FAN_FILE=""
for HWMON in /sys/class/hwmon/hwmon*; do
    [ -f "$HWMON/name" ] || continue
    read -r HNAME < "$HWMON/name" 2>/dev/null || continue
    if [ "$HNAME" = "coretemp" ] && [ -z "$TEMP_FILE" ]; then
        for T in "$HWMON"/temp*_input; do
            [ -f "$T" ] && TEMP_FILE="$T" && break
        done
    elif [ "$HNAME" = "cros_ec" ]; then
        [ -f "$HWMON/fan1_input" ] && FAN_FILE="$HWMON/fan1_input"
    fi
done

[ -n "$TEMP_FILE" ] || { echo "错误：未找到 coretemp 温度传感器（/sys/class/hwmon）"; exit 1; }
[ -n "$FAN_FILE" ] || { echo "错误：未找到 cros_ec 风扇传感器（/sys/class/hwmon）"; exit 1; }

get_cpu_temp()
{
    [ -r "$TEMP_FILE" ] || return 1
    read -r RAW < "$TEMP_FILE" || return 1
    [ -n "$RAW" ] || return 1
    echo $((RAW / 1000))
}

# 实时功耗：上一轮 energy 差分，直接设置全局 POWER
# （不能放在 $( ) 里调用，子 shell 不保留 PREV_E）
RAPL="/sys/class/powercap/intel-rapl:0"
ENERGY_FILE="$RAPL/energy_uj"
PREV_E=""
PREV_T=""
POWER="N/A"
calc_power()
{
    [ -r "$ENERGY_FILE" ] || { POWER="N/A"; return; }
    read -r E < "$ENERGY_FILE" || { POWER="N/A"; return; }
    [ -n "$E" ] || { POWER="N/A"; return; }
    T=$(date +%s%N)

    if [ -n "$PREV_E" ] && [ "$E" -ge "$PREV_E" ] && [ "$T" -gt "$PREV_T" ]; then
        POWER=$(awk -v e1="$PREV_E" -v e2="$E" -v t1="$PREV_T" -v t2="$T" '
            BEGIN {
                dt = (t2 - t1) / 1000000000
                if (dt > 0) printf "%.1f", (e2 - e1) / 1000000 / dt
                else print "N/A"
            }')
    else
        POWER="N/A"
    fi

    PREV_E="$E"
    PREV_T="$T"
}

# CPU 使用率：/proc/stat 与上一轮差分（全局 CPU_USE，约 94us/轮）
PREV_TOTAL=""
PREV_IDLE=""
CPU_USE="N/A"
calc_cpu_use()
{
    read -r _ U N S I IO IRQ SC ST _ < /proc/stat 2>/dev/null || { CPU_USE="N/A"; return; }
    TOT=$((U + N + S + I + IO + IRQ + SC + ST))
    IDL=$((I + IO))

    if [ -n "$PREV_TOTAL" ] && [ "$TOT" -gt "$PREV_TOTAL" ]; then
        DT=$((TOT - PREV_TOTAL))
        DI=$((IDL - PREV_IDLE))
        if [ "$DT" -gt 0 ]; then
            CPU_USE=$(((DT - DI) * 100 / DT))
        else
            CPU_USE="N/A"
        fi
    else
        CPU_USE="N/A"
    fi

    PREV_TOTAL=$TOT
    PREV_IDLE=$IDL
}

# 温度 → 档位（阈值/回差全部来自配置区）
# $1=当前档位 $2=当前温度
calc_rpm()
{
    LVL="$1"
    TEMP="$2"
    NEW="$LVL"

    # 升档：达到阈值
    case "$LVL" in
        1) [ "$TEMP" -ge "$UP1" ] && NEW=2 ;;
        2) [ "$TEMP" -ge "$UP2" ] && NEW=3 ;;
        3) [ "$TEMP" -ge "$UP3" ] && NEW=4 ;;
        4) [ "$TEMP" -ge "$UP4" ] && NEW=5 ;;
        5) [ "$TEMP" -ge "$UP5" ] && NEW=6 ;;
    esac

    # 降档：低于 阈值-回差
    case "$LVL" in
        2) [ "$TEMP" -lt $((UP1 - HYST)) ] && NEW=1 ;;
        3) [ "$TEMP" -lt $((UP2 - HYST)) ] && NEW=2 ;;
        4) [ "$TEMP" -lt $((UP3 - HYST)) ] && NEW=3 ;;
        5) [ "$TEMP" -lt $((UP4 - HYST)) ] && NEW=4 ;;
        6) [ "$TEMP" -lt $((UP5 - HYST)) ] && NEW=5 ;;
    esac

    echo "$NEW"
}

# 档位 → 目标转速（来自配置区 RPM1-6）
rpm_of_level()
{
    case "$1" in
        1) echo "$RPM1" ;;
        2) echo "$RPM2" ;;
        3) echo "$RPM3" ;;
        4) echo "$RPM4" ;;
        5) echo "$RPM5" ;;
        6) echo "$RPM6" ;;
        *) echo "$RPM2" ;;
    esac
}

log()
{
    printf '%s\n' "$1"
}

# 关闭 EC 自动风扇控制，改手动
"$ECTOOL" autofanctrl off >/dev/null 2>&1

trap 'log "退出，已恢复EC自动风扇控制"; "$ECTOOL" autofanctrl on >/dev/null 2>&1' EXIT
trap 'exit 0' INT TERM

LVL="$INIT_LVL"
HOLD=0
TARGET=$(rpm_of_level "$LVL")
"$ECTOOL" pwmsetfanrpm "$TARGET" >/dev/null 2>&1
log "启动，初始${TARGET}转（每${INTERVAL}秒检测，回差${HYST}°C，升档需连续${UP_N}轮）"

# 预采一帧基准，并等满一个检测周期再进主循环：
# 首轮差分窗口完整（≈INTERVAL 秒），首条日志数值才准确
calc_power
calc_cpu_use
sleep "$INTERVAL"

while true; do
    TEMP=$(get_cpu_temp)
    calc_power
    calc_cpu_use

    if [ -n "$TEMP" ]; then
        # 升档滤波计数：连续 UP_N 轮达到当前档升档阈值才允许升档
        TH=9999
        case "$LVL" in
            1) TH=$UP1 ;; 2) TH=$UP2 ;; 3) TH=$UP3 ;; 4) TH=$UP4 ;; 5) TH=$UP5 ;;
        esac
        if [ "$TEMP" -ge "$TH" ]; then
            HOLD=$((HOLD + 1))
        else
            HOLD=0
        fi

        NEW=$(calc_rpm "$LVL" "$TEMP")
        if [ "$NEW" -ne "$LVL" ]; then
            if [ "$NEW" -gt "$LVL" ] && [ "$HOLD" -lt "$UP_N" ] && [ "$TEMP" -lt "$EMERG" ]; then
                :   # 滤波拦截：单轮尖峰不升档（EMERG 以上绕过）
            else
                NEWRPM=$(rpm_of_level "$NEW")
                if "$ECTOOL" pwmsetfanrpm "$NEWRPM" >/dev/null 2>&1; then
                    log "${TEMP}C -> ${NEWRPM}RPM | PWR ${POWER}W | USE ${CPU_USE}%"
                    LVL="$NEW"
                    TARGET="$NEWRPM"
                    HOLD=0
                fi
            fi
        fi
    fi

    # 状态文件：覆盖写，恒为 1 行
    [ -n "$STATUS_FILE" ] && printf "%s | CPU:%sC | USE:%s%% | PWR:%sW | TGT:%sRPM\n" \
        "$(date '+%Y-%m-%d %H:%M:%S')" "${TEMP:-?}" "$CPU_USE" "$POWER" "$TARGET" > "$STATUS_FILE"

    sleep "$INTERVAL"
done
