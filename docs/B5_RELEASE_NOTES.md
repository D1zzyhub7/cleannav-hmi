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

# R10-B5 Release Notes（提交前准备）

- 类型：APP地图显示交付，非A7/R9导航算法版本。
- 默认：C Professional Floorplan；备用：A Faithful Vector。
- 原物理格网511×660、resolution0.05000000074505806、origin[-8.924291610717773,-8.59818172454834,0]；PNG/SVG2044×2640，displayScale4。
- B5相对B4：高清asset/metadata、显示scale归一、底图与overlay共用zoom/pan、解码缓存约束和必要测试。原worldToImage、HTTP、任务/Safety/ESTOP和低频轮询逻辑保持。
- C/B occupied IoU0.941581、area+5.45%、新增距原occupied≤约5cm；unknown变化0，8柱不强制补圆。A语义零变化。仍建议后续补扫未知区，视觉图不得回灌导航。
- Flutter46/46、analyze0、Python7/7为本轮离线结果；4种宽高约束、实际paint、随机投影和pinch/pan对齐覆盖。
- APK独立交付：`cleannav-experiments/cleannav-r10-b5-professional-map-20261108T102042Z/artifacts/cleannav-mobile-r10-b5-professional-map-debug.apk`，SHA256 `828917a906dc61f83fbf0c49eaeb1d9b71713479a6bedf907395e59799795902`，155688028bytes，com.example.cleannav_mobile0.2.1+3/min24/target36。Git不包含APK或实验压缩包，后续可作为GitHub Release附件；本轮未上传。
- 当前main/发布起点6ddff0f88e200136f2462e42e50aaaccab2d3aa6，提交/推送/tag/PR/合并均未执行。
- 未完成：真实手机安装/CPU/RSS/FPS/10～15min稳定性、实车。只读手机步骤见APP_DEVELOPMENT.md。本轮无ROS/Gazebo/手机/业务HTTP/Lease/车辆运动。

发布分支从旧main起，因此完整diff还包括B5所携带、此前未纳入main的R10客户端基线；B5相对B4的7文件差异单独归档。车端Python/Voice保持main，原用户dirty目录不受影响。
