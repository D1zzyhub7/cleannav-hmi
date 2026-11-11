## 2026-11-11 原车电量与 IMU 只读显示（当前源码）

当前手机源码在 2026-11-09 红米客户端上增加总览只读电量和 IMU。样本年龄超过 15 秒或缺失时显示未知。IMU 分三行显示姿态、加速度和角速度，不作为定位。开发者记录默认关闭，只保留手机本机最近 12 行摘要。

手机已在车载 Wi-Fi 上看到电量和 IMU。定位、急停、任务和手机控车未接，不能写成整车联调完成。本仓库 Gateway 源码未改，版本号仍是 0.2.1+3。已安装 Debug APK 不纳入 Git，SHA256 `5968e977ce1c3a1f28cf866b6b6586a276662d8a4101d82525b7504d8f404ac8`。本轮只复跑了电量和 IMU 的契约测试，没有重跑完整回归。说明见仓库根 [README](../README.md)。以下各节是更早的发布记录。

## 2026-11-08 Final RC Closure（当前结论）

**OFFLINE_RC_CANDIDATE_READY**：Analyze无问题、Flutter **70/70 PASS**、Python **7/7 PASS**，已在隔离Linux工具链构建并验签arm64-v8a Debug APK。默认C Professional Floorplan、A备用；地图/坐标/目标配置和A7/R9/B3/B4/B5冻结资产保持。

APK：`offline-hardening-final-rc-20261108T132212Z/artifacts/cleannav-mobile-r10-b5-final-rc-arm64-v8a-debug.apk`（82,281,523 bytes），包名com.example.cleannav_mobile，versionName0.2.1，拆分ABI实际versionCode2003（源码+3）。SHA256 `604f712e5a9ce63c67344ed9835955118e63a35fe19e5d577b6f02eec356bb49`。

新Linux Debug证书与旧Windows Debug证书不同，不能直接覆盖旧签名安装；本轮未处理手机安装/数据。手机稳定性、真实强停恢复与实车仍NOT RUN。Token仅会话保存，重启重填；原明文断言已按明确授权改为安全契约，保留Registry/Charger/地图断言。无Release密钥、Git发布、ROS/Gazebo、Gateway业务/Lease/运动。

[最终报告](../R10_B5_FINAL_RC_RESULT.md) · [测试矩阵](../B5_FINAL_TEST_MATRIX.md) · [SHA256SUMS](../SHA256SUMS)。以下旧结论均为历史时间点，不替代本节。

---

## 2026-11-08 Offline Hardening（当前状态，覆盖下方历史验收结论）

本分支新增任务回执持久化/恢复、状态过期、前后台轮询管理、Token 脱敏与会话保存、配置导入回滚、全页 ESTOP 和 Demo 可见性管理。默认 C Professional Floorplan，A 备用；地图和导航资产未变。未改 Gateway、MM、Safety、Lease、导航 API 或车端源码。

**当前不能称为通过全部回归的 Release Candidate。** 旧测试 `test/hmi_contract_test.dart` 要求明文持久化 Token，与本轮会话 Token 行为冲突；原断言保留，没有改成 PASS。以 [本轮完整结果](../R10_B5_OFFLINE_HARDENING_RESULT.md) 的最终计数为准。Android Release 和 Debug 在当前 WSL 文件系统上均遭 Gradle 文件缓存 I/O 错误，没有生成本轮新 APK。历史 Debug APK 不包含本轮 Dart 修改，仅作为历史调试基线保留。

正式签名尚未配置；已移除 Release 使用 Debug 密钥的回退，不创建密钥。真机安装、进程被系统杀死后的恢复、后台稳定性与实车均未验证。本轮无 commit/push/tag/PR/merge。

# R10-B5 APP 开发与离线验收

B5移动端源码以2026-11-08已验收B5/app为候选；本发布分支仅将该候选纳管，未开发B6。默认C Professional Floorplan，A备用。详见[地图资产说明](MAP_DISPLAY_ASSET.md)。

## 仓库与基线

APP归属 `https://github.com/D1zzyhub7/cleannav-hmi.git`。准备分支 `release/r10-b5-professional-map-20261108`，基于main `6ddff0f88e200136f2462e42e50aaaccab2d3aa6`；main仍为旧APP，diff包含既有R10 V1/B3/B4客户端基线，不能误称只有7个地图文件。相对B4，B5产品只有7项必要显示/测试差异。

Gateway/Voice Python代码在本分支保持原main，未复制用户dirty目录的后端更改。APP需要既有V1/Bearer Gateway服务，历史B1服务端SafetyStatus兼容候选属于独立车端部署；不能把本APP发布分支的旧后端源码当作已部署B1服务，也不在本轮部署。APP当前任务/Safety/ESTOP/Lease边界及接口与B5保持相同；APP不获取Lease或发速度。

## Flutter

已验证工具链Flutter3.47.5 stable / Dart3.13.4，Android Debug min24/target36，com.example.cleannav_mobile，0.2.1+3。版本号沿用B5，凭文件名/SHA区分此前B3/B4。

```bash
cd /path/to/cleannav-hmi
flutter pub get --offline  # 新开发机没有缓存时使用 flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

测试均为离线Mock；不要在本轮运行ROS/Python Gateway整包测试或旧联调runner。`map_display/tools/test_b5.py`是指定的7项离线地图测试。

## Android构建（只在Dart/地图资产变化后）

当前正式交付复用已验证B5 APK，因本轮仅纳管相同产品源码和文档，无需重建。后续真有修改时沿用已验证Windows链：D:\Dev\flutter、Android Studio JBR、Gradle进程参数Xmx1536m/Metaspace512m/CodeCache128m/1worker/parallel=false/daemon=false/Kotlin in-process，从既有build.lock独占入口运行 `flutter build apk --debug --no-pub --verbose`。APK写独立交付目录，不加入Git。

新开发机先安装相同Flutter/Android SDK，配置本机SDK路径；本仓库不提交android/local.properties或生成build目录。原Windows环境前缀不能当作新机器固定路径。

## 离线renderer环境

Ubuntu22.04实际包版本：python3-opencv4.5.4+dfsg-9ubuntu4；python3-numpy1:1.21.5-1ubuntu22.04.1；python3-scipy1.8.0-1exp2ubuntu1；python3-pil9.0.1-1ubuntu0.6；python3-yaml5.4.1-1ubuntu1；python3-cairo1.20.1-3build1；fonts-dejavu-core2.37-2build1。字体路径/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf。未引入新依赖或APP SVG库。

## 后续手机验证（本轮未执行）

1. 用户安排手机与既有Gateway可用后，先核对独立交付APK及SHA，使用同签名 `adb install -r` 保留配置。
2. 打开APP，用管理员提供的URL/Token连接；只读查看Gateway/Mission/Safety状态及C地图，检查车位/朝向/Region/Charger/目标对齐。
3. 总览→任务→连接循环30次、缩放平移，记录APP相关crash/exception、CPU/RSS趋势，连续运行10～15分钟。
4. 不将APK安装成功视为导航或稳定性PASS；不在这组只读检查中提交Task41/43、STOP/ESTOP/RESET。实际运动测试依后续明确任务范围安排。

真实红米闪退根因、手机稳定性、实车均未验收。不要把历史B2“保持运行”的PID当作当前进程事实，也不重放旧session。

## Offline Hardening 使用说明

- Token 只在当前进程内存中保存。启动时移除旧 `gateway_token` 明文项；重启后手动重填。未新增安全存储插件，未宣称实现 Android Keystore。HTTP cleartext 仍保留既有局域网兼容性，不能提供链路加密；受信网络外应使用现有 HTTPS 部署。
- 回执按规范化 Gateway base URL 隔离，保存在 `task_receipts:<base>`。只含 task_id/command_id/sequence_id/status_url，不含 Token。导航提交前落盘（STOP/ESTOP先发送、后尝试保存，不因磁盘失败阻止发送）；202 仅表示接收，不等于完成。重启、重连、前台恢复均只 GET 原 status_url。未知结果或查询失败不自动重新 POST。请勿清除应用数据来“恢复”连接。
- SUCCEEDED/FAILED/REJECTED/CANCELED/EMERGENCY_STOPPED 停止追踪并从持久回执中清除；内存仅保留最近20条终态历史。404/GET timeout 保留身份，显示 UNKNOWN，不宣告成功。回执损坏时保留数据并报告错误，不自动删除再下单。
- 状态新鲜度以最后成功 GET 的本机时间计，默认5秒过期，现有1秒 Timer检查；后台立即清除动态位姿和 Safety/网关状态，取消现有 Timer，前台仅 GET 更新。已有请求 single-flight，回调代次检查避免后台旧结果覆盖。
- 导航任务须 Safety 新鲜且明确未急停；STOP/ESTOP 不等待普通提交完成。ESTOP 入口跨页面保留，即使缓存 Gateway 状态过期仍可尝试既有接口；网络失败不代表车辆已停。RESET 仍需原明确确认，不自动触发，不恢复旧任务。
- 管理员 JSON 完整解析成功并持久写成功后，才替换当前目标。默认仿真目标 IDs/地图身份及静态显示坐标未改，任务页标注 SIMULATION；导入配置的真实性仍由管理员负责。
- Agent Demo 是独立模拟服务，非实车任务入口；离开该页/后台取消其现有轮询，返回页仅恢复 GET，不重新提交模拟计划。

### 重现离线验证

```bash
flutter pub get --offline
flutter analyze --no-pub
flutter test --no-pub
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s map_display/tools -p test_b5.py -v
```

原46项测试未修改预期；新增测试在 `test/offline_hardening_test.dart`。进程恢复测试是销毁内存对象、仅保留序列化存储后重建的 Mock 模型，不等于 Android 系统真实杀进程验证。现有地图测试覆盖随机点、车辆/Region/Charger/目标和缩放/平移，新增页面测试覆盖320×640、800×480、1024×1366。

本机 Flutter3.47.5 / Dart3.13.4 Linux工具准备与执行日志保存在 `offline-hardening-20261108T120552Z/`（Git忽略）；工具链不是产品依赖。Windows SDK 在 WSL 路径的锁/UNC 与 Gradle FileHasher失败见该目录原始日志；没有改用工作树外源码镜像。换机在本地受支持文件系统、同版本Flutter/AndroidSDK/JDK环境重跑以上命令，再构建：

```bash
flutter build apk --release --split-per-abi --no-pub
flutter build apk --debug --no-pub
```

Release 未配置 signingConfig，任何生成物均须核验签名，不能当成生产签名包。保留既有包名com.example.cleannav_mobile、0.2.1+3；min24/target36，Release R8/minify和shrinkResources由当前Flutter插件启用，arm64-v8a在默认split ABI中。Gradle限制1worker/不并行/1536MB堆，沿用现有build.lock；无新增插件或运行时依赖。

### Final RC 原生Linux构建复用

在当前worktree source `offline-hardening-final-rc-20261108T132212Z/env.sh`，执行 `flutter build apk --debug --split-per-abi --no-pub --target-platform=android-arm64`；构建须沿用现有build.lock。仅本地忽略的工具链/缓存与android/local.properties采用Linux路径，不修改系统或原WindowsAndroid环境。JNI现有依赖需要Android35和CMake/Ninja，APP使用Android36。依赖版本和lockSHA保持。APK签名为此隔离环境正常生成的Debug证书；不要据此直接执行历史说明中的跨签名install-r。正式Release和手机操作需后续任务范围。
