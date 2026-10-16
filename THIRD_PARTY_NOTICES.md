# Third-Party Notices

本仓库除以下第三方组件外，其余内容（`crb-fen-ctl2.sh`、`setup-systemd.sh`、
`crb-fen-clt.service`、`README.md`、`fanctl.md` 等）均使用 [LICENSE](LICENSE)
（GPL-3.0 License，Copyright (c) 2026 rrpro）。

## ectool

- 文件：`ectool`（预编译二进制）
- 来源：<https://github.com/DHowett/ectool>
  （从 ChromeOS 源码中抽离，含 Framework 机型适配）
- 许可证：BSD 3-Clause，**全文见下方**
- 版权：Copyright 2010 The ChromiumOS Authors；
  Additions copyright 2024 Dustin L. Howett
- 可自行从上游源码编译并替换本文件，只要支持
  `autofanctrl` / `pwmsetfanrpm` 命令即可

BSD 3-Clause 允许再分发（含二进制），条件是随附版权声明与许可文本——
本文件即为满足该条件而提供。

## ectool 许可证全文（BSD 3-Clause）

```
Copyright 2010 The ChromiumOS Authors
Additions copyright 2024 Dustin L. Howett

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * Neither the name of Google LLC nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
