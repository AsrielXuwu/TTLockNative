# TTLock Native — 原生通通锁蓝牙控制与快捷指令工具

一款基于 **SwiftUI** 与 **CoreBluetooth** 构建的轻量级 iOS 原生智能门锁控制应用。无需依赖官方云端服务器或网关，直接通过手机本地蓝牙与通通锁（TTLock）硬件进行 AES 加密通信，实现毫秒级开/闭锁、状态电量同步及 iOS 快捷指令后台静默自动化。

---

## ✨ 核心特性

- **纯本地蓝牙直连**：直接解析门锁蓝牙广播帧与 GATT 特征值，断网环境下依然可用，无任何云端中转延迟。
- **用完即断的事务型连接**：每次操作遵循「连接 $\rightarrow$ 挑战应答鉴权 $\rightarrow$ 发送加密指令 $\rightarrow$ 立即断开」生命周期，不常驻后台、不消耗额外电量，也不影响其他设备或原版小程序连接门锁。
- **完整门锁控制能力**：
  - **开锁 / 闭锁**：支持四宫格卡片及顶部大锁徽章一键切换开闭状态，附带系统级触感反馈（Haptic Feedback）。
  - **状态与电量同步**：App 启动及切换门锁时自动连接读取当前锁舌状态与电池百分比。
  - **蓝牙校时**：一键将手机系统时间同步至门锁内部时钟。
- **多门锁管理与导入**：支持实时扫描周边通通锁蓝牙广播（自动提取 MAC 地址、协议版本与信号强度），或直接粘贴抓包/导出的 `lockData` 参数配置多把门锁并随时切换。
- **iOS 快捷指令后台静默运行**：深度集成 `AppIntents`，支持通过 Siri、快捷指令、控制中心、iPhone 动作按钮或地理围栏自动化在**不拉起前台界面**的情况下静默开关指定门锁。

---

## 🎨 原生 iOS 26/27 液态玻璃交互设计

- **Liquid Glass 原生材质**：全面采用 SwiftUI 原生 `.glassEffect` 与 `.buttonStyle(.glass)` / `.glassProminent` 构建操作面板与圆形状态徽章，自动适配浅色与深色模式。
- **iMessage 风格滚动收起动效**：通过 `onScrollGeometryChange` 实时追踪滚动位移，页面上滑时顶部大锁图标与状态文字无缝缩放并收敛为导航栏中央的紧凑液态玻璃胶囊（支持直接点击切换锁态）。
- **原生分组表单布局**：采用系统级 `Form` 与 `LabeledContent` 展示实时蓝牙通道状态、电池电量及设备硬件协议参数。

---

## ⚡ iOS 快捷指令（Shortcuts）配置说明

应用内置了两个完全独立的快捷指令动作，支持多门锁动态参数选择：

1. **打开门锁**：后台自动连接选定门锁并执行开锁。
2. **关闭门锁**：后台自动连接选定门锁并执行闭锁。

### 后台免扫描直连加速机制
由于 iOS 系统在后台模式下会限制蓝牙广播扫描频率，本项目在 `LockShortcuts.swift` 中实现了 **`PeripheralUUIDCache` 双通道连接引擎**：
- 首次成功连接门锁后，自动将系统分配的 `CBPeripheral.identifier` 持久化缓存。
- 后续在后台或锁屏状态下触发快捷指令时，直接通过 `retrievePeripherals` 发起点对点直连（跳过广播扫描，通常 1~2 秒内完成开/关锁）；若缓存失效则自动无缝回退至后台扫描兜底。

### 使用步骤
1. 打开 App 完成至少一次门锁添加与连接（授予蓝牙权限）。
2. 添加 **「打开门锁」** 或 **「关闭门锁」** 操作，点击蓝色 **「门锁」** 参数选择目标门锁；lockData请自行从微信小程序抓包获取，填入lockData后可自动解析核心鉴权参数
3. 展开操作详情并关闭 **「运行时显示」**，即可实现完全无打扰的后台静默执行。
4. 打开系统 **「快捷指令」App** $\rightarrow$ 新建快捷指令 $\rightarrow$ 搜索本应用名称。

---

## 📂 项目结构

```text
├── project.yml                         # XcodeGen 工程配置文件（含 bluetooth-central 后台权限声明）
├── .github/workflows/                  # GitHub Actions 云端自动构建工作流（输出免签 IPA）
└── Sources/
    ├── Bluetooth/
    │   └── TTLockBLEManager.swift      # 前台 CoreBluetooth 状态机、分包重组与超时控制
    ├── Crypto/
    │   └── TTLockCrypto.swift          # 通通锁帧封装、CRC 校验与 AES-128-CBC 加解密
    ├── Models/
    │   └── LockModels.swift            # 门锁数据模型（SmartLock）与本地持久化（LockStore）
    ├── Intents/
    │   └── LockShortcuts.swift         # AppIntents 快捷指令实体查询与后台无界面 BLE 执行器
    └── UI/
        ├── ContentView.swift           # 主控制界面、滚动收起顶栏动效与门锁管理列表
        ├── AddLockView.swift           # 蓝牙扫描与手动录入配置界面
        └── LiquidGlass.swift           # 原生液态玻璃样式封装与系统版本兼容层
```

---

## 🛠️ 构建与安装

### 方式一：GitHub Actions 云端自动编译（推荐）
本项目使用 **XcodeGen** 管理工程结构，无需本地安装 macOS 或 Xcode 即可完成构建：
1. Fork 或推送代码至你的 GitHub 仓库。
2. 前往仓库的 **Actions** 页面运行构建工作流，编译完成后在 **Artifacts** 中下载生成的 `.ipa` 安装包。
3. 使用 **TrollStore（巨魔商店）**、**AltStore** 或 **SideStore** 安装到 iPhone 即可使用。

### 方式二：macOS 本地编译
确保已安装 Xcode 与 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
# 生成 Xcode 工程文件
xcodegen generate

# 打开工程进行真机调试或打包
open TTLockNative.xcodeproj
```

---

## 🔐 蓝牙通信协议简述

| 参数项 | 规格说明 |
| :--- | :--- |
| **GATT Service UUID** | `00001910-0000-1000-8000-00805F9B34FB` |
| **写入特征值 (TX)** | `0000FFF2-0000-1000-8000-00805F9B34FB` (`writeWithResponse`) |
| **通知特征值 (RX)** | `0000FFF4-0000-1000-8000-00805F9B34FB` (`notify`) |
| **帧头标识** | `0x7F 0x5A`（支持多包分片自动拼接与长度校验） |
| **鉴权与加密** | 基于动态随机数挑战（`checkUserTime`）与门锁专属 AES Key / `unlockKey` 加密负载 |

---

## ⚠️ 免责声明

- 本项目仅用于个人合法拥有的智能门锁设备的技术研究、本地化控制与无障碍快捷指令自动化，严禁用于任何未经授权的设备访问或逆向破解用途。
- 请妥善保管你的门锁 `aesKey` 与 `unlockKey` 数据，切勿将包含真实门锁密钥的配置文件上传至公开代码仓库。