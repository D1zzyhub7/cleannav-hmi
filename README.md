# CleanNav 人机交互与语音模块

本仓库用于 CleanNav 决赛阶段的人机交互系统，统一维护手机 APP、PC/WSL HMI Gateway 和离线语音模块。

当前仓库主要包含：

- Flutter Android 手机 APP
- PC / WSL HMI Gateway
- 离线语音识别与语音任务入口

APP 和 Voice 都只负责上层任务交互，不允许直接控制车辆。

禁止 APP 或 Voice：

- 发布 `/cmd_vel`
- 直接发送 CAN 控制命令
- 修改 Ackermann 参数
- 绕过 Mission Manager 直接控制 Navigation
- 绕过 Safety 建立第二条车辆控制链路

---

## 1. 仓库结构

~~~
cleannav-hmi/
├── lib/                     Flutter APP
├── android/                 Android 配置
├── test/                    Flutter 测试
├── cleannav_hmi_gateway/    PC / WSL HMI Gateway
├── scripts/                 HMI 辅助脚本
├── package.xml
├── setup.py
└── voice/                   CleanNav 离线语音模块
    ├── cleannav_voice/
    ├── config/
    ├── test/
    ├── package.xml
    ├── setup.py
    └── README.md
~~~

Voice 原先作为独立的本地 `cleannav-voice` 仓库开发。

并入本仓库时的 Voice 基线为：

~~~
c4e09c8a8cfa897ab85d4bbeff9b808125b410b4
~~~

原来的本地 `cleannav-voice` 仓库继续保留，用于历史追溯和回退。

---

## 2. 系统架构

### APP 链路

~~~
手机 Flutter APP
        |
        | HTTP
        v
PC / WSL HMI Gateway :18082
        |
        | HTTP
        v
J6M HIL :18081
        |
        v
Mission Manager
        |
        v
Navigation
~~~

APP 只发送上层任务请求。

手机 APP 本身不发送 `source`，HMI Gateway 转发给 J6M 时统一设置：

~~~
source = APP = 2
~~~

### Voice 链路

~~~
麦克风 / WAV / 离线 ASR
        |
        v
RecognizedUtterance
        |
        v
TextNormalizer
        |
        v
IntentParser
        |
        v
VoicePolicy
        |
        v
TaskCommand(source=VOICE)
        |
        v
Mission Manager
~~~

APP 与 Voice 复用相同的 TaskCommand / Mission Manager 接口，但输入链路相互独立。

Voice 音频不通过手机 APP 转发。

---

## 3. 手机 APP

当前比赛 APP 的主要开发分支：

~~~
feature/m1-competition-app
~~~

当前版本已经移除早期 Demo Transport 和 BLE Transport。

APP 通过 HMI Gateway 与 CleanNav 系统通信。

当前比赛任务：

~~~
task_id = 30
key = CLEAN_NEAREST_LEAF
中文含义 = 清扫最近的落叶
~~~

APP 会为任务生成唯一 `command_id`。

---

## 4. HMI Gateway

Gateway 默认监听：

~~~
0.0.0.0:18082
~~~

主要 HTTP API：

| 方法 | 地址 | 作用 |
| --- | --- | --- |
| GET | `/api/state` | 获取 Gateway、J6、车辆和任务状态 |
| GET | `/api/map` | 获取 RTAB 地图和机器人位姿 |
| POST | `/api/tasks` | 提交上层任务 |
| POST | `/api/emergency-reset` | 软件急停复位请求 |

APP 会分别显示：

- Gateway 是否连接
- J6 是否连接
- 定位是否正常
- 自动驾驶是否允许
- 急停状态
- 当前任务状态

`/api/state` 返回 HTTP 200 只表示 Gateway 本身可以访问。

如果：

~~~
j6_connected = false
~~~

表示 J6 当前没有连接，不代表 Gateway 断开。

---

## 5. 地图显示

当前 APP 使用真实 ROS2 数据：

~~~
/rtabmap/map
/rtabmap/localization_pose
~~~

支持真实 OccupancyGrid：

- 未知区域显示为灰色
- 空闲区域显示为白色
- 障碍区域显示为深灰或黑色
- 处理 ROS 地图 Y 轴与屏幕坐标差异
- 使用地图 origin
- 使用地图 resolution
- 使用地图 yaw
- 定位有效时显示机器人位置和方向

如果没有真实地图，APP 不显示虚假的路线、目标点或机器人轨迹。

---

## 6. APP 当前验证状态

已经验证：

- `flutter pub get` 通过
- `flutter analyze` 通过
- Flutter 测试 12 / 12 通过
- Android Debug APK 构建通过
- Android 真机安装通过
- 真机离线界面通过
- Task 30 页面通过
- Gateway 与 J6 状态可以独立显示
- 无真实地图时不显示虚假地图
- 手机到 PC / WSL HMI Gateway 通信通过

当前已经实际验证：

~~~
手机 APP
→ PC / WSL HMI Gateway
~~~

该链路为 PASS。

由于最近一次 APP 验证时手边没有 J6M，因此以下链路仍待最终实机联调：

~~~
手机 APP
→ HMI Gateway
→ J6M
→ Mission Manager
→ Navigation
→ 实车
~~~

不能将当前状态描述成“APP 到整车已经全部打通”。

---

## 7. Flutter 开发环境

当前验证环境：

~~~
Flutter 3.47.5
Dart 3.13.4
Android SDK 36
NDK 28.2.13676358
~~~

常用命令：

~~~
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
~~~

---

## 8. HMI Gateway 环境

当前 PC 环境：

~~~
Windows 11
WSL2 Ubuntu 22.04
ROS2 Humble
~~~

常用 ROS2 环境：

~~~
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=42
export ROS_LOCALHOST_ONLY=0
~~~

Gateway 示例启动：

~~~
source /opt/ros/humble/setup.bash
source <cleannav_interfaces_install>/setup.bash
source <cleannav_hmi_install>/setup.bash

ros2 run cleannav_hmi_gateway cleannav_hmi_gateway --ros-args \
  -p bind_host:=0.0.0.0 \
  -p port:=18082
~~~

---

## 9. Voice 模块

Voice 现在位于：

~~~
voice/
~~~

ROS2 包名：

~~~
cleannav_voice
~~~

Voice 正式输出话题：

~~~
/cleannav/hmi/task_command
~~~

Voice 来源：

~~~
SOURCE_VOICE = 1
~~~

正式处理逻辑：

~~~
RecognizedUtterance
→ TextNormalizer
→ IntentParser
→ VoicePolicy
→ TaskCommandFactory
→ VoiceBridgeNode
~~~

Voice 不直接调用 Navigation 或 Safety。

---

## 10. SenseVoice 当前状态

当前比赛阶段已经完成 PC 侧 SenseVoice 验证。

SenseVoice 使用外部 sherpa-onnx 运行环境和模型。

已经实际验证过的任务语句包括：

~~~
清扫最近的落叶
~~~

该语句可以映射为 Task 30。

大型 SenseVoice 模型文件和 Python 虚拟环境不存入 Git 仓库。

历史上已经完成过以下 HIL 链路：

~~~
SenseVoice
→ RecognizedUtterance
→ VoicePolicy
→ TaskCommand(source=VOICE)
→ J6 HTTP HIL
→ Mission Manager
→ PC Navigation HIL
→ Gazebo
~~~

---

## 11. SenseVoice J6M 部署

当前 SenseVoice 主要运行在 PC 侧。

决赛下一阶段计划：

~~~
SenseVoice / ONNX
→ 地平线模型转换
→ HBM
→ J6M BPU
~~~

J6M BPU 侧部署目前尚未最终验证。

因此不能描述为“SenseVoice 已经在 J6M BPU 上稳定运行”。

---

## 12. Voice 构建

Voice 现在作为本仓库中的独立 ROS2 子包存在。

推荐显式构建：

~~~
colcon build --base-paths <cleannav-hmi路径>/voice
~~~

主要依赖：

~~~
cleannav_interfaces
rclpy
ament_index_python
PyYAML
~~~

---

## 13. 冻结基线

CleanNav 跨仓库 HIL 冻结标签：

~~~
competition-hil-baseline-20260921
~~~

HMI 在该基线之后继续开发了 M1 Competition APP。

禁止重写已经共享的基线历史，禁止 force push 稳定基线。

---

## 14. 后续工作

本仓库后续主要任务：

1. APP 与实际 J6M 在线联调
2. 实车 TaskStatus 回传
3. 实车状态显示
4. SenseVoice ONNX 整理
5. SenseVoice HBM 转换
6. J6M BPU 验证
7. APK 正式发布和签名
8. 决赛完整系统联调

后续开发应保持当前 APP、Gateway 和 Voice HIL 基线可复现。
