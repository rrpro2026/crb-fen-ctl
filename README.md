# crb-fen-ctl — Chromebox 风扇温控

Chromebox/Chromebook 简单风扇温控 Linux 脚本，基于 ectool 运行，支持 systemd 后台运行，按温度档位自动调速


## 文件（仅 3 个）

| 文件 | 作用 |
|------|------|
| `crb-fen-ctl2.sh` | 主脚本（最终版，可执行）：5 秒检测，静默运行，只在转速变化时输出一行 |
| `setup-systemd.sh` | 一键安装/卸载 systemd 服务（可执行，`sudo` 运行） |
| `ectool` | Google ChromeOS EC 工具二进制（BSD-3-Clause，安装时复制到 `/usr/local/bin/`） |

来源 [DHowett/ectool](https://github.com/DHowett/ectool)，**可自行编译更换**，安装时复制到 `/usr/local/bin/` |
## 快速开始

```bash
git clone https://github.com/rrpro2026/crb-fen-ctl.git && cd ./crb-fen-ctl
sudo ./setup-systemd.sh
```

安装内容：ectool → `/usr/local/bin/`、按实际路径生成 `crb-fen-clt.service`、开机自启并立即运行。

```bash
systemctl status crb-fen-clt          # 状态
journalctl -u crb-fen-clt -f          # 跟踪日志
sudo ./setup-systemd.sh remove        # 卸载（自动恢复 EC 自动风扇控制）
```

不装服务直接跑：

```bash
sudo ./crb-fen-ctl2.sh
```

## 温控策略

CPU 最高温 → 目标转速，升档立即、降档需低于阈值 5°C（回差）：

| 温度 | 转速 |
|------|------|
| < 45°C | 1500 RPM |
| 45–55°C | 2000 RPM |
| 55–65°C | 2800 RPM |
| 65–75°C | 3800 RPM |
| 75–80°C | 4500 RPM |
| ≥ 80°C | 5600 RPM（满速） |

## 配置

全部集中在 `crb-fen-ctl2.sh` 头部配置区（第 18-51 行），改完保存即生效：

```sh
ECTOOL=""      # 留空自动探测：脚本同目录 → /usr/local/bin
INTERVAL=5     # 检测间隔（秒）
HYST=5         # 回差（°C）
STATUS_FILE="" # 单行状态文件，留空不写
INIT_LVL=2     # 启动档位（1-6）
UP1=45 UP2=55 UP3=65 UP4=75 UP5=80            # 升档阈值（°C）
RPM1=1500 RPM2=2000 RPM3=2800 RPM4=3800 RPM5=4500 RPM6=5600  # 各档转速
```

也可环境变量临时覆盖，不改文件：

```bash
sudo INTERVAL=10 UP1=50 ./crb-fen-ctl2.sh
```

单行状态文件（每轮覆盖，恒 1 行，随时 `cat` 查看）：

```bash
sudo STATUS_FILE=/tmp/fan.status ./crb-fen-ctl2.sh
```

## 日志

平时静默，只在转速变化时输出（时间由 journal 显示，脚本不加前缀）：

```
Start, init 2000RPM (every 5s, hyst 5C)
56C -> 2800RPM | PWR 8.3W | USE 12%
Exit, auto fan on
```

| 字段 | 来源 |
|------|------|
| 温度 | coretemp 各核心最高值 |
| PWR | RAPL `energy_uj` 相邻两轮差分 ÷ 实际耗时 |
| USE | `/proc/stat` 两轮差分 CPU 使用率 |

## 要求与行为

- root（`/dev/cros_ec`、`energy_uj` 只有 root 可读）
- systemd、coretemp、cros_ec 内核驱动（`ls /sys/class/hwmon/` 可见）
- 性能：实测 systemd 统计约 **0.35% 单核 + 1.2MB 内存**（5 秒一轮，含全部子进程）
- 安全：正常退出 / 服务停止（SIGTERM）都会通过 trap 恢复 `autofanctrl on`；崩溃由 systemd 5 秒后拉起
- 风扇有固件最低转速限制，1500 若低于 min 实际转速下不去

## 临时排错

```bash
sudo /usr/local/bin/ectool autofanctrl on     # 手动恢复自动风扇
sudo /usr/local/bin/ectool pwmsetfanrpm 3000  # 手动试转速
systemd-analyze verify crb-fen-clt.service    # 校验 service
```

> ⚠️ **仅在ASUS Chromebox 3 CN65（Debian 13）测试通过**，其他硬件/系统未适配，换机器请按需自行修改：
>
> 1. **温度传感器**：按名称探测 `coretemp`（Intel），AMD 改为 `k10temp`
> 2. **风扇接口**：依赖 `ectool` 的 EC 命令，非 Chrome 设备用 `pwm`/`fancontrol` 替换
> 3. **转速档位表**：`UP1-5` 阈值与 `RPM1-6` 转速需按你的散热重新标定
> 4. **功耗字段**：`PWR` 读 Intel RAPL，AMD 换路径或删除该字段


## 许可证

- 本仓库脚本与文档：GPL-3.0（[LICENSE](LICENSE)，Copyright (c) 2026 rrpro）
- `ectool` 二进制：BSD 3-Clause，来源 [DHowett/ectool](https://github.com/DHowett/ectool)，
  许可证全文见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

