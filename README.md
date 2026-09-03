# CleanNav 手机 APP v0.2.0

Flutter 原生 Android/iOS 控制端，支持本地演示、HTTPS 网络和 BLE 蓝牙三种连接方式。
APP 继续遵循 CleanNav 冻结接口 v1.0，只发送 task_id，不直接发送速度、路径或自由坐标。

## 已实现功能

- 车辆状态：离线、待机、规划、导航、清扫、暂停、返航、充电、急停和异常；
- 状态详情：电量、速度、定位、刷盘、水泵/吸水机构、任务进度和连接类型；
- 13 个冻结任务：task_id 1–7、10、20、30–33；
- 软件急停和独立现场安全复位；
- 三种连接模式：演示、HTTPS、BLE；
- 七套差异化地图路线与动作表现。

## 差异化任务演示

| task_id | 任务 | 地图与车辆行为 |
| --- | --- | --- |
| 1 | 开始清扫 | 全区域弓字形覆盖，刷盘和水泵开启 |
| 5 | 返回起点 | 从当前位置生成独立返航轨迹，清扫机构关闭 |
| 10 | 前往一号点 | 点到点导航，仅行驶不清扫 |
| 20 | 执行一号路线 | 沿闭合预设路线连续清扫 |
| 30 | 清扫落叶 | 接近目标后局部回旋，刷盘开启 |
| 31 | 清扫落叶堆 | 低速接近，扩大覆盖范围，刷盘与水泵开启 |
| 32 | 处理积水 | 沿积水边缘环绕，吸水机构开启 |
| 33 | 最优先目标 | 导航到最高优先级目标后进行组合清扫 |

## 首次生成 Android/iOS 工程

源码包没有包含数百 MB 的 Flutter 构建缓存。安装 Flutter 3.27 或更高版本后执行。

Windows PowerShell：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\bootstrap.ps1
flutter run
```

Linux/macOS：

```bash
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
flutter run
```

脚本会生成标准 `android/`、`ios/` 目录，加入蓝牙权限，执行依赖安装、静态分析和测试。

## 网络连接

在 APP“连接”页面填写：

```text
https://你的域名/api/bridge
```

网络适配器调用：

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET | `/api/state` | 车辆、任务与设备状态 |
| POST | `/api/tasks` | 下发普通任务 |
| POST | `/api/emergency-reset` | 安全确认后解除急停 |

API 地址必须是手机可访问的地址。正式部署应使用可信 HTTPS、短期访问令牌、用户/车辆
权限、操作审计、限流和重放保护，不应把无认证 ROS 2 Bridge 直接暴露在公网。

当前冻结 `RobotStatus.msg` 没有电池、充电、刷盘和水泵字段，因此现有 Bridge 下这些
项目会显示“未提供”或关闭；演示模式可完整展示。实车若要显示这些状态，应由车辆状态
聚合节点在 HTTP/BLE 状态中增加 `battery`、`charging`、`brush_on`、`water_pump_on`，
或在下一版接口规范中正式扩展消息，不能由 APP 随意猜测设备状态。

## BLE 蓝牙连接

开发阶段预留 UUID：

```text
Service: 0000c100-0000-1000-8000-00805f9b34fb
Command: 0000c101-0000-1000-8000-00805f9b34fb
State:   0000c102-0000-1000-8000-00805f9b34fb
```

- Command characteristic：APP 写入 UTF-8 JSON，每帧以换行结束；
- State characteristic：车端 Notify UTF-8 JSON 状态；
- task_id 7 必须携带 `safety_confirmed: true`；
- 所有报文携带 `interface_version: "1.0"`。

这些 UUID 是开发占位值。接入实车前必须与车端固件统一，并增加设备绑定、挑战应答、
会话密钥和防重放计数。BLE 不应绕过车辆本地 Safety Supervisor。

## 构建安装包

Android 调试安装：

```bash
flutter build apk --debug
```

Android 正式包：

```bash
flutter build appbundle --release
```

iOS 必须在 macOS/Xcode 环境配置 Apple 开发者签名后执行：

```bash
flutter build ipa --release
```

## 联调顺序

1. 先在演示模式逐项验证七套任务路线和车辆状态；
2. 网络模式接现有 APP Bridge，核对 `/api/state` 字段；
3. 确定车端 BLE UUID、MTU、分帧、应答和鉴权协议；
4. 真机测试断网、断蓝牙、急停、重复指令和状态超时；
5. 最后接 Mission Manager 与 Safety Supervisor。
