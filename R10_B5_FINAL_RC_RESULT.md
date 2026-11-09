# R10-B5 Final RC Closure

状态：**OFFLINE_RC_CANDIDATE_READY**。2026-11-08，仅离线 Debug 候选；没有手机安装、真机稳定性或实车验收。

## 最终交付

- [arm64-v8a Debug APK](offline-hardening-final-rc-20261108T132212Z/artifacts/cleannav-mobile-r10-b5-final-rc-arm64-v8a-debug.apk)，**82,281,523 bytes（78.47 MiB）**。
- 包名 `com.example.cleannav_mobile`，versionName `0.2.1`，实际APK versionCode **2003**。源码仍0.2.1+3；Flutter分ABI为arm64添加2000的版本码偏移，未伪称APK版本码3。
- SHA256：`604f712e5a9ce63c67344ed9835955118e63a35fe19e5d577b6f02eec356bb49`。
- [最终测试矩阵](B5_FINAL_TEST_MATRIX.md)、[校验清单](SHA256SUMS)。APK和本地工具链位于Git忽略目录，不加入普通源码提交。

## 回归结果

|项目|结果|真实证据|
|---|---|---|
|flutter analyze --no-pub|rc0，无问题|offline-hardening-final-rc-20261108T132212Z/analyze.log|
|flutter test --no-pub --concurrency=1|rc0，**70/70 PASS**|offline-hardening-final-rc-20261108T132212Z/flutter-tests.log|
|Python地图测试|rc0，**7/7 PASS**|offline-hardening-final-rc-20261108T132212Z/python-tests.log|
|Linux arm64 Debug构建|rc0，Gradle116任务，assembleDebug约221秒|offline-hardening-final-rc-20261108T132212Z/debug-build.log|
|APK签名与badging|验证成功；Android Debug签名；debuggable=true；min24/target36|offline-hardening-final-rc-20261108T132212Z/apk-signature.log、apk-badging.log|
|APK ABI|仅arm64-v8a|offline-hardening-final-rc-20261108T132212Z/apk-verification.json|
|APK内四资产|map.png、map.json、display metadata、app_targets均与源码逐字节一致|offline-hardening-final-rc-20261108T132212Z/apk-verification.json|
|B3/B4/原B5/A7-R9保护|203/203、242/242、148/148、30/30全匹配|offline-hardening-final-rc-20261108T132212Z/protected-assets-final.json|
|源文件差异与校验|git diff --check通过；SHA256SUMS实际逐项核验|offline-hardening-final-rc-20261108T132212Z/diff-check.log、checksum-check.log|

最终回归在Linux私有Pub缓存/SDK配置和APK构建完成后再次顺序执行，并非沿用旧63/64结果。测试均使用Mock/Fake HTTP，无真实Gateway请求。初次新增日志捕获参数重复命名造成的Dart编译错误已修正（原语言版本3.3不支持重复`_`形参）；失败日志保留为initial证据，不冒充最终结果。

## Token契约闭环

原 `test/hmi_contract_test.dart:444` 所在整个测试保留；Registry目标、未配置Charger、地图身份不匹配、无导航POST和配置持久化断言全部保留。本轮获明确授权后只替换明文Token断言并补充安全断言，见 [token-contract.diff](offline-hardening-final-rc-20261108T132212Z/token-contract.diff)。

- SharedPreferences的gateway_token为空；当前控制器仍持有Token。
- 实际Mock请求带Authorization: Bearer；不是只检查字符串构造。
- 新控制器initialize后Token为空、不发送Authorization，原Registry和地图配置仍恢复。
- Mock服务端401消息含Token时，异常、controller.error、回执message/response及print/debugPrint捕获日志均不含Token。
- 新契约的源码证据：[test/hmi_contract_test.dart:424](test/hmi_contract_test.dart)。未恢复明文持久化，未删除整个测试，未放宽其他断言。

Token仍仅存内存，重启后须重填；未新增Keystore/Flutter插件。既有HTTP cleartext保留，链路加密边界未改变。

## 未知POST结果与UI

Transport没有修改（本轮起止SHA相等）；复用既有导航POST前持久化、原身份恢复、同一status_url查询、未知结果防重复提交和终态清理。增加的UI仅显示原status_url以及明确人工核对提示，见 [tasks_page.dart:22](lib/screens/tasks_page.dart)。

新增 [final_rc_ui_test.dart](test/final_rc_ui_test.dart) 六项测试：响应丢失、POST timeout、202、GET暂不可用、恢复回执的五种显示，以及身份损坏时保留记录并阻止导航POST。未知状态明确显示UNKNOWN/待核对，202为ACCEPTED，均不能误示SUCCEEDED；原command_id/status_url可见。身份损坏时不删除记录、不自动重建第二个任务。原Task41/43序列化恢复、GET timeout后续查询、无重复POST等测试继续通过。

“强停后恢复”当前仍是丢弃内存对象、仅保留序列化存储再重建的离线模型。真实Android强停/掉电写入和实际Gateway状态恢复尚未测；如果用户清除全部应用数据，APP没有新API可以发现任意既有任务，必须人工核对，不自动下单。

## 构建环境闭环

初始只读事实：PATH中的flutter/dart指向D盘Windows SDK；java为Linux11；sdkmanager不存在；ANDROID_HOME/ANDROID_SDK_ROOT为空。Linux doctor明确缺Android SDK；Chrome/GTK/桌面clang不是Android构建前提，未为此扩展安装。

先报告缺项及最小方案后，在本worktree忽略目录完成隔离补齐，没有写D盘、原HMI/Android环境或系统配置：

- 复用现有Linux Flutter3.47.5/Dart3.13.4工具源/ELF二进制，补本地CLI入口；实际which/native file证据 `offline-hardening-final-rc-20261108T132212Z/native-environment.log`。
- Linux Corretto JDK17.0.21、官方Linuxcommand-line tools19.0、Android platforms35（现有JNI插件需要）和36、build-tools36.0.0、platform-tools37.0.1、NDK28.2.13676358、CMake/Ninja3.22.1。
- Gradle9.1.0分发、既有依赖和包缓存只读复制到worktree私有目录，实际由LinuxJava运行；没有执行WindowsJava/UNC构建。
- 首次下载中途停滞/SSL EOF后，标准curl断点续传及刷新缓存URL完成Linuxarchive下载。试用现有command-line23的Java库不能启动SDKManager，记录失败并改用完整官方Linux19归档，未保留该失败入口为最终工具。
- 第一次原生构建失败于生成元数据仍含Windows Pub路径；在私有缓存重新执行flutter pub get --offline。复制缓存一度缺少hosted-hashes使pub尝试去除锁文件校验字段；已从冻结原B5中恢复与本轮起点SHA相等的锁文件，复制并核对54份既有归档哈希，重新pub get无告警。**pubspec.yaml和pubspec.lock最终逐字节保持本轮起点，依赖未升级。**
- android/local.properties为本机忽略文件，现指隔离LinuxSDK/Flutter。配置在 `offline-hardening-final-rc-20261108T132212Z/env.sh`；未改用户shell profile或全局Flutter配置。
- 使用既有build.lock、1536m堆/512m Metaspace/128m CodeCache和1worker，日志确认为Using1 worker leases；没有colcon或ROS构建。构建成功无OOM，资源原始数据保留；不能把离线构建推定为手机性能PASS。

实际命令（当前worktree）：

```bash
source offline-hardening-final-rc-20261108T132212Z/env.sh
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest discover -s map_display/tools -p test_b5.py -v
flock /home/d1zzy/code/cleannav_modularization/cleannav-build/locks/build.lock \
  flutter build apk --debug --split-per-abi --no-pub --target-platform=android-arm64
```

实际构建额外带--verbose供证据记录，仅选择arm64，符合优先交付arm64要求。旧Windows路径错误和首次native路径错误均已解决，不再是当前构建阻塞。

## Debug签名与手机安装边界

新APK通过正常Android Debug签名机制生成，未创建正式Release密钥、未伪造签名、未构建正式Release。新Debug证书SHA256 `b3cb28ed2cdfaac8759973761dfb6e983526106b0808776e112ca83d12acf664`；历史Windows Debug证书 `7ad7b862a40a3df535f887f0f3477d318469d4efdd8828dfc0dd42d39dbcb893`。

两者不同：**如果红米当前安装的是旧证书版本，新APK不能直接覆盖安装保留数据。** 后续安装安排需明确处理签名兼容和数据保留（例如另行授权复用原Debug密钥再构建）；本轮不复制旧私钥、不卸载手机APP、不清手机配置或回执。新包可用于匹配该签名的安装环境或首次安装。此已知升级边界不改变本轮离线候选就绪状态。

## 地图与保护资产

原511×660、resolution=0.05000000074505806、origin=[-8.924291610717773,-8.59818172454834,0]和displayScale4未改。C PNG2044×2640，SVG viewBox0 0 511 660；物理范围25.55000038072467×33.00000049173832m未裁剪/旋转/平移。原Registry默认pillar_v1/charger_sim_01身份与坐标正确，app_targets字节未改。

|资产|SHA256|
|---|---|
|assets/map.png|291489b2fdd57cd40866f15a13c8f78165ca214988e4eab04208c1e38832a5e3|
|assets/map.json|16568650a9126ea955d0eb0a645f63956f801a7c1a2a913227b8e3075296778f|
|assets/map_display_metadata.json|1a0cb32677ce2ae2d863f9b65d768d19e8c9b2dc78fd9d761bc797fea706da0c|
|assets/app_targets.json|368c064b6941daa57628cb90a452d553882006cf3b2141acff29d6bd8191c9c2|
|map_display/outputs/map_professional_floorplan.svg|831d5d095075fde94f481848aa772950062b668ef9a7dbf094d1ae3cd7d6ea3a|

B3/B4/原B5 APP/A7-R9合计623项冻结文件全部重新哈希匹配；未改原HMI worktree、Navigation仓库、导航算法、车端接口或地图。所有产品写操作仅在 `/home/d1zzy/code/cleannav_modularization/cleannav-experiments/cleannav-r10-b5-professional-map-20261108T102042Z/finalization-20261108T111729Z/release-worktree`，旧报告/旧APK保留。

## 源码与文档范围

- 本轮产品改动仅lib/screens/tasks_page.dart、test/hmi_contract_test.dart，以及新增test/final_rc_ui_test.dart。
- README、docs/APP_DEVELOPMENT.md、docs/OPERATIONS_RUNBOOK.md、docs/B5_RELEASE_NOTES.md和APP作用域PROJECT_MASTER/B5_COMMIT_PLAN追加当前结论，保留旧报告历史；根项目文档未写入。
- 分支release/r10-b5-professional-map-20261108，HEAD仍6ddff0f88e200136f2462e42e50aaaccab2d3aa6，index空；无commit/push/tag/PR/merge。原有48文件基线和Hardening工作均保留。

## 尚未验证/结束

真机安装、红米闪退是否解决、10～15min前后台稳定性、CPU/RSS/FPS、真实进程强停与回执落盘、真实Gateway/任务及车辆运动仍NOT RUN。Debug包有调试开销，不等于Release性能。正式Release签名/发布本轮不要求，未执行。

未连接手机、未运行ADB命令、未启动/终止ROS/Gazebo、未访问真实Gateway业务、未申请Lease或控制车辆。工具托管任务均正常收尾，0新集成终端、0手工后台任务；最终进程与锁证据见 `offline-hardening-final-rc-20261108T132212Z/cleanup.json`。新调试密钥留在忽略的本地Android用户目录，不作为源码或交付清单内容。

Shared Memory updated: cleannav_next_actions、cleannav_validation_status、cleannav_session_20261108_r10_b5_final_rc_closure。
