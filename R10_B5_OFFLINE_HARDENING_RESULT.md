# R10-B5 Offline Hardening Result

日期：2026-11-08。范围：APP离线可靠性加固与候选审查；**当前未达到全量PASS/正式Release可交付状态**。

完成源码审计、必要修复、18项新增Mock测试、既有测试回归、地图/保护资产核验、Release/Debug构建尝试及文档。仍有1项旧Token断言冲突和本机APK构建环境失败；不隐藏失败，不改旧测试预期，不用旧APK代替新代码。

## 仓库与48文件起点

- 唯一修改位置：`/home/d1zzy/code/cleannav_modularization/cleannav-experiments/cleannav-r10-b5-professional-map-20261108T102042Z/finalization-20261108T111729Z/release-worktree`。
- remote：`https://github.com/D1zzyhub7/cleannav-hmi.git`。
- branch：`release/r10-b5-professional-map-20261108`；HEAD/main基线 `6ddff0f88e200136f2462e42e50aaaccab2d3aa6`。
- 开始时48个改动/未跟踪文件，index空。这48文件已经包含R10 V1/B3/B4/B5，相对旧main并非只有地图改动。逐文件审查：[BASELINE_48_REVIEW.md](offline-hardening-20261108T120552Z/BASELINE_48_REVIEW.md)，开始SHA/状态：[baseline.json](offline-hardening-20261108T120552Z/baseline.json)。
- 本轮修改14个原48文件，另有必要的main生命周期、Android构建配置、忽略项、测试和APP作用域文档。最终完整文件清单：[file-list.json](offline-hardening-20261108T120552Z/file-list.json)。
- 没有修改原HMI worktree或Navigation；这两个仓库HEAD、分支、dirty状态和cached状态与此前finalization证据完全一致。新commit=0，index仍空，无push/tag/PR/merge。

## 主要缺陷与修复

1. 原回执仅在内存，断线重连关闭Transport后丢失。现在导航POST前持久保存原身份；恢复只GET原status_url，未知结果不重下单，终态清除恢复记录。磁盘失败不阻止STOP/ESTOP先行发送。
2. 原界面可能继续展示缓存Safety/网关状态。增加本地接收时间过期处理，复用原1秒Timer；后台停止轮询并清空状态/位姿，前台只查询原请求。状态/回执各自single-flight，不新增轮询器。
3. 原Token明文持久化且服务端回显可能进入错误文本。当前仅会话保存、移除旧明文项，并脱敏HTTP JSON/异常。重启必须重新填Token。这有意改变旧Token持久化行为，并与1项原测试断言冲突。
4. 原普通导航提交未在控制器检查急停/未知Safety；当前明确禁止这类空间任务。STOP和ESTOP仍严格区分、不中断彼此的既有接口语义；共用底栏ESTOP在所有页面可用，离线缓存不会阻止发送尝试。RESET仍明确确认，不自动复位、不自动恢复旧任务。
5. 管理员导入原先先变更内存再保存；当前完整验证并写成功后才替换。默认Region/Charger/地图身份与冻结仿真Registry逐字段一致，无需改坐标；任务页显式SIMULATION。
6. Demo独立模拟页已有业务隔离；补充明确标签、隐藏页和后台暂停其原Timer，回来仅GET；修正非法Safety标量导致的异步TypeError风险，保留页Controller/订阅/Client正常释放。
7. 限制内存终态历史20条。静态底图与动态层、原坐标投影、低频位姿更新及图像缓存路径保持原样，未引入新图片/安全存储插件。
8. Release原来回退Debug签名，现移除；Gradle内存由8G改为既有1536m/512m/128m和1worker。未创建任何密钥。

## 源码审计（行号对应本轮最终文件）

|项目|审计结果与处理|源码证据|
|---|---|---|
|Task41/43 提交|既有Task41/43目标和map身份负载保留，command/sequence各自关联；不增加API。|[lib/services/http_transport.dart:9](lib/services/http_transport.dart#L9)|
|回执持久化|原回执只在内存；新增SharedPreferences非秘密回执，按规范化Gateway URL隔离。导航POST前先落盘，存储失败不发新导航POST。|[lib/controllers/app_controller.dart:122](lib/controllers/app_controller.dart#L122)|
|恢复/202|只恢复command_id、sequence_id、原status_url；状态先UNKNOWN；202仅ACCEPTED，不能直接当SUCCEEDED。|[lib/services/http_transport.dart:177](lib/services/http_transport.dart#L177)|
|POST关联|POST返回command_id/sequence_id若不匹配则保留UNKNOWN；status_url只允许同Gateway V1相对地址，禁止外域/点路径。|[lib/services/http_transport.dart:312](lib/services/http_transport.dart#L312)|
|GET关联与超时|GET验证command/sequence身份；timeout/404/格式错误仅显示查询不可用并保留原身份。single-flight，不重新POST。|[lib/services/http_transport.dart:359](lib/services/http_transport.dart#L359)|
|重复POST|已有未终态空间请求（含UNKNOWN）阻止第二次空间提交；恢复/前台回归只GET。|[lib/services/http_transport.dart:266](lib/services/http_transport.dart#L266)|
|终态清理|SUCCEEDED/FAILED/REJECTED/CANCELED/EMERGENCY_STOPPED不再GET且不再持久保存。保留最多20条内存终态历史；没有自动重试执行队列。|[lib/services/http_transport.dart:94](lib/services/http_transport.dart#L94)|
|Token存储|原版本明文gateway_token；本轮启动移除旧记录、仅保存在进程内，重启后重填；不引入Keystore插件，也不假装加密存储。|[lib/controllers/app_controller.dart:62](lib/controllers/app_controller.dart#L62)|
|日志与服务端回显|生产lib无print/debugPrint；HTTP JSON字符串/错误消息统一脱敏Token。会话Token不写入任务回执。|[lib/services/http_transport.dart:149](lib/services/http_transport.dart#L149)|
|Authorization|保留Authorization: Bearer，GET/POST使用同一header，不向Agent Demo传Token。|[lib/services/http_transport.dart:133](lib/services/http_transport.dart#L133)|
|HTTP失败|保留HTTP状态码/原因、非JSON/异常提示；无Token的异常保持原类型（TimeoutException等），含Token异常替换安全错误文本。|[lib/services/http_transport.dart:165](lib/services/http_transport.dart#L165)|
|Gateway/MM过期|最后成功GET超过默认5秒后按原1秒Timer转UNKNOWN（最迟约6秒）；MM订阅计数在robot不新鲜时不再声称在线。不是新增MM心跳API。|[lib/services/http_transport.dart:205](lib/services/http_transport.dart#L205)|
|Safety1.0/1.1|使用聚合器已有available/fresh字段和公共字段，无需APP重复解析ROS消息；过期/非法bool为null，未知block_all保持UNKNOWN。|[lib/models/hil_snapshot.dart:164](lib/models/hil_snapshot.dart#L164)|
|single-flight|状态请求、回执GET各自互斥；Task41/43受既有运行请求限制；连接入口保留_connecting互斥。|[lib/services/http_transport.dart:220](lib/services/http_transport.dart#L220)|
|前后台|后台取消原Timer、失效Gateway/Safety/位姿；前台恢复GET，代次检查抑制后台晚回包。后台初始化先读回执，不开始HTTP。|[lib/services/http_transport.dart:416](lib/services/http_transport.dart#L416)|
|STOP/ESTOP|仍分别/api/v1/stop与/api/v1/estop。它们不等普通任务busy、不因Safety缓存过期阻止发送，也不等待磁盘后才发送；落盘失败仅明确记录。|[lib/controllers/app_controller.dart:208](lib/controllers/app_controller.dart#L208)|
|全页ESTOP|原只在总览且触发后被RESET替换；新增共用底栏急停按钮，任务/连接/Demo页也能操作。未配置连接时无法发送，离线请求不等于实车已停。|[lib/screens/home_shell.dart:58](lib/screens/home_shell.dart#L58)|
|急停任务保护|导航必须Safety新鲜、emergencyStop明确false且blockAll不true；不会在急停或UNKNOWN时发普通导航。|[lib/controllers/app_controller.dart:223](lib/controllers/app_controller.dart#L223)|
|RESET|仍只通过用户显式确认请求；未新增自动RESET路径；没有恢复旧导航任务的代码。|[lib/screens/overview_page.dart:438](lib/screens/overview_page.dart#L438)|
|默认Registry|app_targets.json的地图身份/Region/Charger IDs与A7仿真Registry一致；map.json两处坐标逐字段比对一致，无需改资产。|[assets/app_targets.json:3](assets/app_targets.json#L3)|
|目标坐标|Region(13.815102233908052,-6.831575183979148,0)，Charger(6.8,-3.2,-0.46801971206933923)。客户端只提交注册ID，坐标来自冻结显示资产。|[assets/map.json:16](assets/map.json#L16)|
|管理员错误导入|先完整解析验证、写入成功后才替换内存配置；JSON/结构/重复ID/持久化错误保留已有有效配置。|[lib/controllers/app_controller.dart:257](lib/controllers/app_controller.dart#L257)|
|SIMULATION|任务页明确默认目标是SIMULATION仿真配置；导入配置需管理员核对身份，APP不把ID存在当成实车安全证明。|[lib/screens/tasks_page.dart:19](lib/screens/tasks_page.dart#L19)|
|Demo隔离|原已有simulation-only检查和独立/api/agent，现导航标签明确Demo演示。仅用户操作可能调用，测试全Mock，不接正式任务接口。|[lib/controllers/agent_demo_controller.dart:125](lib/controllers/agent_demo_controller.dart#L125)|
|Demo轮询|原IndexedStack隐藏页会继续400ms轮询；新增可见/前后台状态取消既有Timer，回页只GET原计划，不重新POST。|[lib/controllers/agent_demo_controller.dart:214](lib/controllers/agent_demo_controller.dart#L214)|
|资源释放|页TextEditingController和DemoController在dispose释放；AppController和Transport取消订阅/Timer并关闭自有HTTP client；延迟返回不通知已销毁对象。|[lib/controllers/app_controller.dart:302](lib/controllers/app_controller.dart#L302)|
|图片/重绘|保留Image.asset/ImageCache、随DPR/viewport限decodeWidth、RepaintBoundary；未新增解码器或SVG依赖。静态图与低频mapPose overlay分离。|[lib/widgets/mission_map.dart:218](lib/widgets/mission_map.dart#L218)|
|多尺寸地图|worldToImage、displayScale=4、统一InteractiveViewer/Stack变换未修改；512随机点/旋转origin/实绘缩放平移测试继续覆盖。|[lib/widgets/mission_map.dart:230](lib/widgets/mission_map.dart#L230)|
|空/错误状态|断网、过期、缺字段显示UNKNOWN/不可用；非法Safety标量不再抛出TypeError逃逸Timer；无合法定位时隐藏车辆。|[lib/models/hil_snapshot.dart:187](lib/models/hil_snapshot.dart#L187)|
|Android网络|INTERNET权限保留；usesCleartextTraffic=true沿用既有局域网HTTP兼容，Token在HTTP链路上仍无加密。没有擅改Gateway部署。|[android/app/src/main/AndroidManifest.xml:7](android/app/src/main/AndroidManifest.xml#L7)|
|Release签名|原release签debug；已移除该回退，未提供正式密钥，不生成或伪造密钥。当前不能宣称正式签名发行。|[android/app/build.gradle.kts:31](android/app/build.gradle.kts#L31)|
|Gradle资源|原8G堆/4G Metaspace改为已验证1536m/512m/128m，1worker/parallel=false/daemon=false/Kotlin in-process，使用既有独占build.lock。|[android/gradle.properties:1](android/gradle.properties#L1)|


## 自动化验证与真实边界

|检查|本轮真实结果|证据|
|---|---|---|
|flutter analyze --no-pub|rc=0，无问题|offline-hardening-20261108T120552Z/analyze-linux.log|
|flutter test --no-pub --concurrency=1|rc=1，**63 PASS / 1 FAIL，共64**|offline-hardening-20261108T120552Z/test-linux.log|
|新增18项测试|18/18 PASS|test/offline_hardening_test.dart|
|原46项回归|45 PASS / 1 FAIL；原文件全部未修改|offline-hardening-20261108T120552Z/original-tests-unchanged.json|
|Python地图测试|7/7 PASS|offline-hardening-20261108T120552Z/python-tests.log|
|PNG/SVG/物理元数据|2044×2640，viewBox 0 0 511 660，displayScale=4|offline-hardening-20261108T120552Z/map-asset-check.json|
|投影/尺寸/覆盖层|原512随机点、多viewport实绘/缩放/平移和新增3尺寸页面循环PASS|Flutter完整日志|
|Registry/地图坐标|地图身份、两个ID、entry/staging x/y/yaw一致|offline-hardening-20261108T120552Z/registry-consistency-check.json|
|git diff --check|rc=0|offline-hardening-20261108T120552Z/diff-check.log|
|SHA256SUMS|生成后逐项实际校验，结果见日志|offline-hardening-20261108T120552Z/checksum-check.log|

唯一失败是原 `test/hmi_contract_test.dart:444`：`expect(prefs.getString('gateway_token'), 'test-only-token')`，当前实际null。其前面的Registry身份和Charger保护断言已经通过；失败点不是这两个功能。没有修改该文件或任何旧测试预期。新测试独立证明Token不落盘且回执跨控制器恢复。要通过原断言必须恢复明文持久化，或经用户审查后维护该历史断言；本轮保留安全行为和原失败证据，不宣称64/64。

新增用例包括Task41/43序列化后销毁内存对象重建、手动重连/前后台、202查询、真实GET timeout后继续GET、未知POST结果不重复POST、三种终态清理、保存失败禁止导航但不阻止STOP/ESTOP、Token回显脱敏、Safety公共字段1.0/1.1和非法值、错误JSON回滚、急停/复位、320×640/800×480/1024×1366页面反复进出、Demo隐藏暂停和后台初始化连接。全部使用Fake/Mock HTTP，无业务网络访问。

测试中的“杀进程恢复”是丢弃全部内存状态、仅保留序列化存储再构建控制器/Transport的离线模型；没有杀手机进程，没有证明Android强停、磁盘掉电原子性或真机稳定性。Safety1.0/1.1验证的是已有Gateway聚合JSON的公共字段，非连接ROS消息类型。

实际cwd均为本worktree。Flutter3.47.5/Dart3.13.4；Windows工具从WSL映射路径遇到Swift/文件锁问题，仅停止本Agent拥有的卡住进程。随后在本worktree忽略目录组装同版本Linux Dart/Flutter引擎，Linux执行以上完整命令；没有新产品依赖。完整准备命令/失败迭代/最终stdout、stderr和rc均在证据目录。早期迭代不是最终结果：包含已修复的测试资产异步加载、代码lint/重复参数和旧异常类型问题；新Demo测试以`pollInterval`推进一个周期，未改变断言值。

## Android Release 审查与APK

- 包名 `com.example.cleannav_mobile`；版本 `0.2.1+3`。版本沿用候选，当前未制作可安装新包。
- Flutter插件当前默认minSdk24/targetSdk36，compileSdk36，split ABI含armeabi-v7a/arm64-v8a/x86_64。INTERNET已配置，HTTP cleartext保留既有局域网兼容性；**HTTP下Bearer链路仍明文**，不宣称传输安全。
- Release R8/minify/shrinkResources由Flutter3.47.5插件启用（FlutterPlugin.kt:218附近），本项目未关闭；没有成功二进制可核实实际裁剪结果。现有运行时依赖仍仅http/shared_preferences，无新增插件/业务API。
- 原Release signingConfig使用debug，已删除。未配置正式签名，不创建或伪造密钥；没有生产签名包。
- 实际尝试 `flutter build apk --release --split-per-abi --no-pub --verbose` 和 `flutter build apk --debug --no-pub --verbose`，均rc1，未生成本轮APK。
- 首错：Windows Java从WSL映射路径定位wrapper properties失败；仅在worktree内用已安装Gradle验证绕过wrapper路径问题后，真实首错为Gradle FileHasher的 `java.io.IOException: 函数不正确`，`FileDispatcherImpl.lock0/DefaultFileLockManager`。这是此文件系统上的Windows文件锁限制，尚未进入Dart/Android源码编译，不能报告为源码编译PASS或FAIL。临时生成wrapper已恢复，iOS临时移位也已原样恢复；完整Git diff无iOS变化。
- 两组原始构建日志为 `offline-hardening-20261108T120552Z/release-build-initial.log`、`debug-build-initial.log` 和 `release-build.log`、`debug-build.log`；构建使用原build.lock，memory/swap/PSI无压力。未改用授权外的D盘镜像，未扩建Linux Android SDK/JDK链。

|交付物|包名/版本|SHA256 / 字节|状态|
|---|---|---|---|
|本轮Release APK|com.example.cleannav_mobile / 0.2.1+3（配置值）|无|构建环境失败，未生成；无正式签名|
|本轮Debug APK|同上（配置值）|无|构建环境失败，未生成|
|历史B5 Debug（仅基线备用）|com.example.cleannav_mobile / 0.2.1+3|828917a906dc61f83fbf0c49eaeb1d9b71713479a6bedf907395e59799795902 / 155688028|不含本轮Dart加固，不能替代新APK|

历史APK：`/home/d1zzy/code/cleannav_modularization/cleannav-experiments/cleannav-r10-b5-professional-map-20261108T102042Z/artifacts/cleannav-mobile-r10-b5-professional-map-debug.apk`。原构建收据结束时间2026-11-08T18:42:21.6379529+08:00；当前重新核验SHA、大小和4个内嵌地图/目标资产完全一致，证据 `offline-hardening-20261108T120552Z/historical-apk-check.json`。没有安装手机。

## 地图SHA与未修改证明

|资产|SHA256（前后一致）|
|---|---|
|assets/map.png|291489b2fdd57cd40866f15a13c8f78165ca214988e4eab04208c1e38832a5e3|
|assets/map.json|16568650a9126ea955d0eb0a645f63956f801a7c1a2a913227b8e3075296778f|
|assets/map_display_metadata.json|1a0cb32677ce2ae2d863f9b65d768d19e8c9b2dc78fd9d761bc797fea706da0c|
|map_display/outputs/map_professional_floorplan.svg|831d5d095075fde94f481848aa772950062b668ef9a7dbf094d1ae3cd7d6ea3a|
|map_display/inputs/map.pgm|6ffc9e6a249aa6f3504dbd9688b5c84bf35f9fae7d67ea07e53ea5050bad7e76|
|map_display/inputs/map.yaml|1f317300780f08aba52462b45ad1d2457526780cd18a1d29fa63061d7054789f|
|map_display/inputs/occupancy_grid.json|b09fd48018fa0e8b83aa24f66c76d8feec9dc5ab4d79633a2e1ea90743b4410f|

原始511×660格网、resolution=0.05000000074505806、origin=[-8.924291610717773,-8.59818172454834,0]保持。物理范围25.55000038072467m × 33.00000049173832m，无旋转/裁剪/平移。C PNG/SVG、map.json、display metadata均逐字节等于本轮开始SHA，renderer及三种地图算法未改。

保护核验：B3 **203/203**、B4 **242/242**、原B5 APP **148/148**、A7/R9导航资产 **30/30** 全部匹配历史冻结清单。默认APP目标与A7 Registry逐字段相同。原HMI/正式Navigation的HEAD/branch/status/index均与此前证据一致。根目录PROJECT_MASTER/Runbook/README没有写入，本轮所要求的当前状态仅更新APP worktree同名文档，遵守唯一可写范围。

## 完整diff与审查文件

- [所有候选文件相对main完整binary diff](offline-hardening-20261108T120552Z/full-product.diff)（包括未跟踪源码/资产，无暂存）。
- [相对初始48文件的已改文件SHA](offline-hardening-20261108T120552Z/hardening-modified-baseline-files.json)；[可与原B5字节确认的本轮mobile diff](offline-hardening-20261108T120552Z/hardening-mobile.diff)。后者不是全部产品diff；前者包含文档状态变化。
- [48文件逐项审查](offline-hardening-20261108T120552Z/BASELINE_48_REVIEW.md)、[源码证据](offline-hardening-20261108T120552Z/SOURCE_AUDIT.md)、[原测试不变证明](offline-hardening-20261108T120552Z/original-tests-unchanged.json)。
- README、docs/APP_DEVELOPMENT.md、APP范围PROJECT_MASTER.md、docs/OPERATIONS_RUNBOOK.md、docs/B5_RELEASE_NOTES.md已更新当前状态，保留历史内容；[B5_COMMIT_PLAN.md](B5_COMMIT_PLAN.md)仅供后续审查，不执行提交。

## 尚未完成与后续真机清单

1. 审查会话Token安全行为与历史明文持久化断言的冲突。现有失败原样保留，不通过改测试预期伪造全绿；当前不满足全量回归通过条件。
2. 在受支持文件系统和正式工具链内构建本轮Release/Debug；配置真实发布签名后，实际检查签名、ABI/R8、包名/版本/SHA/大小及内嵌地图。当前没有本轮APK，不能进入手机验收。
3. Token持久安全存储没有实现（无新增复杂插件/平台桥），因此选用会话Token；HTTP cleartext仍是部署层未解决项。未更改车端契约、网关路由或TLS部署。
4. 另获手机授权后：对新APK验签/验SHA，安装；先用Mock服务检查强停/重启只GET原回执、不重复POST、202后断网恢复、GET timeout、三类终态清理、背景10～15分钟、页面30次、旋转/多比例/地图pinch-pan；记录crash/ANR/CPU/RSS/位姿对齐。不要清数据绕过未知任务。
5. 真实Gateway与车辆STOP/ESTOP/RESET/Task41/43、实车和导航稳定性仍NOT RUN。手机安装成功、离线测试通过都不等于实车PASS；后续动作必须另有明确任务授权。

本轮无ROS/Gazebo启动/停止，无手机连接，无真实Gateway业务HTTP，无任务/Lease/速度/车辆运动，无Git发布动作。新集成终端0；命令使用工具托管Shell，未创建需保留的手动后台任务。长任务/卡住测试只处理本Agent PID，最终Dart/FlutterTester/Java拥有进程均已退出，build.lock已释放；明细见证据目录process/cleanup文件。保护进程未启动、未终止。

Shared Memory Checkpoint：更新cleannav_next_actions、cleannav_validation_status，并创建cleannav_session_20261108_r10_b5_offline_hardening。旧46/46/旧APK结论只对历史B5有效。
