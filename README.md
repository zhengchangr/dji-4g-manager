<div align="center">

<img src="Resources/AppIcon.iconset/icon_256x256@2x.png" width="120" alt="DJI 4G Manager 图标"/>

# DJI 4G Manager

**大疆 4G 模块的 macOS 管理器 · Native DJI 4G module manager for macOS**

状态 · 短信 · eSIM · USB 上网 · AT 调试

[⬇️ 下载最新版](https://github.com/zhengchangr/dji-4g-manager/releases)

</div>

DJI 4G Manager 是一个把大疆 4G 模块变成“Mac 上可管理、可上网的 4G 设备”的免费开源工具。它通过模块自带的 USB 口直接通信，不修改模块固件；原生 SwiftUI 编写，运行在菜单栏与窗口里，不需要常驻网页服务。

> 本项目是独立开发的非官方第三方工具，与 DJI、Quectel 及运营商无隶属关系。模块为数据向设计，不支持通话语音，因此不包含来电功能。

English: DJI 4G Manager is an independent open-source utility for macOS that talks to DJI 4G modules over USB. It provides live modem status, SMS send/receive, eSIM profile management, USB tethering mode switching and real-time traffic monitoring — built with SwiftUI for macOS 15 and later.

## 主要功能

| 功能 | 状态 | 说明 |
|---|---|---|
| 一 / 二代模块识别 | ✅ | 自动区分一代（2ca3:4006）与二代（2ca3:4009），界面显示代际与 USB 标识 |
| 二代模块提示 | ✅ | 二代模块管理口封闭，提示“仅网卡模式” |
| 模块状态 | ✅ | 运营商、信号、网络制式、SIM 状态、IMEI、号码（AT+CNUM，失败时读 SIM 本机号码电话簿）、IP |
| USB 上网模式切换 | ✅ | 模式 0（管理）/ 1（上网）/ 2 / 3，切换后自动重启模块 |
| 实时流量监控 | ✅ | 网卡、默认路由、实时上/下行速度、本次会话总流量 |
| 短信收发 | ✅ | PDU 编解码（GSM 7-bit / UCS2），支持长短信分段修复与“第 x/y 段”标注 |
| 短信通知 | ✅ | 新短信系统通知 |
| eSIM Profile 管理 | ✅ | EID、Profile 列表、启用/停用/改名/删除（SGP.22 标准指令） |
| AT 调试 | ✅ | 任意 AT 指令与常用指令快捷按钮 |
| 软件内更新 | ✅ | 打开设置自动检查 GitHub 新版本，下载校验后一键替换重启 |
| 单元测试 | ✅ | 短信编解码、AT 解析、本机号码回退、eSIM 协议、网络解析、更新与代际判断（40 项） |

## 支持的模块

| 模块 | USB ID | 支持情况 |
|---|---|---|
| 一代模块 | `2ca3:4006` | 完整管理：状态、短信、eSIM、AT 调试、上网模式切换 |
| 二代模块 | `2ca3:4009` | 仅识别与网卡提示：管理口被封闭；macOS 识别出网卡后可查看网卡与实时流量（待真机验证） |

## 下载与安装

前往 [Releases](https://github.com/zhengchangr/dji-4g-manager/releases) 下载最新版本。

1. 解压 `DJI4GManager-Release.zip`；
2. 将 `DJI4GManager.app` 拖入“应用程序”或直接双击运行；
3. 若 macOS 提示“无法验证开发者”，请右键 `DJI4GManager.app` → 打开。

> 当前版本 0.2.4：使用临时签名、未做 Apple Developer ID 公证，首次打开可能需要在「系统设置 → 隐私与安全性」中允许。

## 使用

1. 将 SIM 卡插入大疆一代 4G 模块并打开 DJI 4G Manager：
   <img width="600" alt="模块接入前界面" src="https://github.com/user-attachments/assets/a06ff1e9-1fec-4e4e-977c-27843735d644" />
2. 使用支持数据传输的 USB-C 线连接模块与 Mac：
   <img width="600" alt="模块已连接" src="https://github.com/user-attachments/assets/69ddf80f-f1dd-44a5-bd41-a75df7b203fa" />
3. 启动应用后自动识别模块；侧边栏可切换状态、短信、eSIM、上网与 AT 调试页面。
4. 「上网」页选择模式 1（USB 上网）并应用，模块重启后系统网络设置会出现 Baiwang 网卡：
   <img width="600" alt="上网模式与流量" src="https://github.com/user-attachments/assets/94341995-8153-4d57-ad28-247245fa1d06" />
5. 若插入的是二代模块，软件会提示“仅网卡模式”：状态、短信、eSIM、AT 调试不可用。macOS 在「系统设置 → 网络」中把 Baiwang 网卡识别出来并显示已连接后，可在「上网」页查看网卡并切换默认出口。

## 从源码构建

要求：

- Xcode 26 或更新（含 macOS 26 SDK）
- Apple Silicon Mac（M 系列）
- 最低 macOS 15（Liquid Glass 玻璃效果需 macOS 26+）

步骤：

1. 打开 `DJI4GManager.xcodeproj`；
2. 选择 `DJI4GManager` scheme 与本机（My Mac）；
3. Command-R 运行。

运行测试：

```
xcodebuild -project DJI4GManager.xcodeproj -scheme DJI4GManager test
```

项目内置 libusb 1.0.30（已随源码编译进应用），无需 Homebrew 或任何外部依赖。

## 技术说明

- USB 传输：libusb 1.0.30（darwin 后端），通过 bulk 端点与模块 AT 接口通信。
- AT 指令：状态查询、`AT+QCFG="usbnet"` 模式切换、`AT+CFUN=1,1` 重启、`AT+CMGL/CMGS` 短信、`AT+CCHO/CGLA/CCHC` eUICC APDU 通道。
- 短信：完整 PDU 解析（GSM 7-bit / UCS2），自动识别长短信分片头并跳过，避免乱码。
- 网络：读取 `ifconfig` / `route` / `netstat -ibn` 识别模块网卡、默认出口与流量。
- 界面：SwiftUI `NavigationSplitView`；macOS 26+ 启用系统 Liquid Glass 玻璃效果，旧系统自动回退为普通磨砂材质。
- eSIM：SGP.22 ES10c 命令（STORE DATA 0x80/0xE2 + TLV），参考 lpac 实现。

## 路线图

- [x] eSIM Profile 管理（SGP.22）
- [x] 短信系统通知
- [x] 长短信分段乱码修复
- [x] 菜单栏快捷入口与实时网速
- [x] 真机验证 USB/AT 通信与模式切换
- [ ] eSIM Profile 下载（SM-DP+ 激活码）
- [ ] Apple 开发者签名与公证（消除首次打开的拦截提示）

## 许可

- 应用代码：MIT License，见 [LICENSE](LICENSE)。
- 内置 [libusb 1.0.30](https://libusb.info)，LGPL-2.1-or-later，许可证见 `Packages/CLibusb/COPYING`。

## 参考与致谢

本项目在开发过程中参考了以下社区项目与资料（仅参考思路与公开 AT/协议信息，未复制代码）：

- [lpac](https://github.com/estkme-group/lpac)：eUICC SGP.22 指令格式参考
- [CdricZhang/dji-cellular-as-modem](https://github.com/CdricZhang/dji-cellular-as-modem)：模块 AT 指令与 USB 模式研究
- [ppqing/dji-4g-notes](https://github.com/ppqing/dji-4g-notes)：一代模块硬件与固件折腾记录
- [wlzh/dji-4g-vohive-mac](https://github.com/wlzh/dji-4g-vohive-mac)：macOS 下模块上网方案参考

与 DJI、Quectel 及各运营商均无隶属关系；本项目为非官方第三方工具。
