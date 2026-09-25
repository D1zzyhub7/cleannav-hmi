# CleanNav 离线语音模块

本模块负责 CleanNav 的离线语音任务入口。

Voice 原先作为独立的本地 `cleannav-voice` Git 仓库开发。

决赛阶段为了方便 APP 与 Voice 统一维护，现并入：

~~~
cleannav-hmi/voice/
~~~

原独立 Voice 仓库导入基线：

~~~
c4e09c8a8cfa897ab85d4bbeff9b808125b410b4
~~~

原本地仓库继续保留，用于历史追溯和回退。

---

## 1. 模块职责

Voice 负责：

~~~
音频输入
→ 离线语音识别
→ 文本规范化
→ 意图识别
→ 安全策略检查
→ TaskCommand
~~~

Voice 只产生上层任务命令。

Voice 不允许：

- 发布 `/cmd_vel`
- 直接控制 CAN
- 直接生成 Ackermann 控制量
- 直接调用 Navigation
- 直接修改 Safety
- 自己维护 Mission Queue
- 绕过 Mission Manager 控制车辆

---

## 2. ROS2 包

包名：

~~~
cleannav_voice
~~~

节点入口：

~~~
voice_bridge_node
~~~

正式输出：

~~~
/cleannav/hmi/task_command
~~~

任务来源：

~~~
SOURCE_VOICE = 1
~~~

---

## 3. 目录结构

~~~
voice/
├── cleannav_voice/
│   ├── asr/
│   ├── audio/
│   ├── demo_hil_http_bridge.py
│   ├── demo_voice_node.py
│   ├── intent_parser.py
│   ├── models.py
│   ├── task_command_factory.py
│   ├── text_normalizer.py
│   ├── voice_bridge_core.py
│   ├── voice_bridge_node.py
│   └── voice_policy.py
├── config/
│   └── voice_task_map.yaml
├── test/
├── package.xml
├── setup.py
└── setup.cfg
~~~

---

## 4. 正式处理链路

~~~
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
TaskCommandFactory
        |
        v
VoiceBridgeNode
        |
        v
/cleannav/hmi/task_command
~~~

各层职责保持分离。

---

## 5. 文本与意图策略

`TextNormalizer` 只进行保守处理，包括：

- Unicode NFKC
- 首尾空白清理
- 大小写统一
- 常见中英文标点删除
- 连续空白压缩

`IntentParser` 使用精确匹配策略。

未知语句不会被猜成最接近的任务。

任务语句配置：

~~~
config/voice_task_map.yaml
~~~

---

## 6. VoicePolicy

以下情况拒绝任务：

- 文本无法匹配允许任务
- confidence 不是有限数值
- confidence 不在 `[0, 1]`
- confidence 低于准入阈值
- Task 不存在
- Task 未启用
- Task 不允许 VOICE
- Task 要求人工确认

当前语音准入阈值：

~~~
0.80
~~~

ASR confidence 只表示识别可信度，不表示用户人工确认。

正常 Voice TaskCommand：

~~~
user_confirmed = false
~~~

---

## 7. TaskCommand

Voice 最终生成：

~~~
cleannav_interfaces/msg/TaskCommand
~~~

常见 command ID：

~~~
voice:<utterance_id>
~~~

不符合约束时使用稳定 SHA-256 ID。

原始识别文本保存在：

~~~
raw_text
~~~

时间戳使用 ROS Clock。

Voice 不自行生成导航目标点。

---

## 8. ASR 边界

当前代码已经建立离线 ASR 抽象：

~~~
OfflineAsrBackend
AsrResult
RecognizedUtterance
OfflineAsrPipeline
~~~

ASR 层只负责：

~~~
音频
→ 识别结果
~~~

ASR 层不负责：

- Intent 匹配
- Task 映射
- 0.80 准入判断
- ROS 发布
- TaskCommand 生成

---

## 9. WAV 输入

当前 WAV 输入要求：

~~~
单声道
16 kHz
PCM16
未压缩 WAV
~~~

当前核心模块不会自动执行：

- 重采样
- 双声道转单声道
- VAD
- 唤醒词
- TTS

这些功能后续应独立扩展。

---

## 10. SenseVoice 当前状态

当前比赛阶段已经完成 PC 侧 SenseVoice 验证。

使用外部 sherpa-onnx 环境和 SenseVoice 模型。

已经验证的语句包括：

~~~
清扫最近的落叶
~~~

该语句可以映射为：

~~~
task_id = 30
~~~

大型模型和 Python 虚拟环境不提交到 Git。

---

## 11. 已验证 HIL 链路

已经完成过：

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

因此 Voice 任务入口已经具备可复现的 HIL 基线。

---

## 12. J6 HTTP HIL

源码包含：

~~~
cleannav_voice/demo_hil_http_bridge.py
~~~

历史 J6M 默认地址：

~~~
http://192.168.8.10:18081
~~~

实际运行时地址应保持可配置，不应把比赛现场网络写死在核心代码中。

---

## 13. J6M BPU 状态

SenseVoice 当前仍主要运行在 PC 侧。

下一阶段目标：

~~~
SenseVoice / ONNX
→ 地平线模型转换
→ HBM
→ J6M BPU
~~~

当前尚未完成最终 J6M BPU 部署验证。

---

## 14. 测试

当前测试覆盖：

- ASR Pipeline
- WAV Source
- TextNormalizer
- IntentParser
- VoicePolicy
- TaskCommandFactory
- VoiceBridgeNode
- HIL HTTP Bridge

核心任务策略测试不依赖真实麦克风和大型 ASR 模型。

---

## 15. 构建

开发基线：

~~~
Ubuntu 22.04
ROS2 Humble
~~~

推荐构建：

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

## 16. 后续开发边界

后续必须继续保持：

~~~
音频 / ASR
    |
    v
RecognizedUtterance
    |
    v
VoicePolicy
    |
    v
TaskCommand
    |
    v
Mission Manager
~~~

APP 和 Voice 可以复用相同任务接口，但输入链路保持独立。

Voice 不通过 APP 转发音频，也不能成为第二条车辆控制链路。
