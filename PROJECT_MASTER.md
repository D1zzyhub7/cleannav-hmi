## 2026-11-09 手机仿真业务已完成（当前源码）

红米已用兼容 APK 完成仿真链路：Task43 成功、行驶中 STOP 取消、行驶中 ESTOP 锁存、Task7 复位、复位后 Task41 成功。随后源码只改了总览文案和速度零值显示。已安装 APK 仍是改显示之前的包。地图扫描覆盖不在这次提交里改变。

## 2026-11-08 Debug 覆盖安装签名兼容（当前交付）

最新兼容包：`offline-hardening-phone-compat-20261108T142237Z/cleannav-mobile-r10-b5-final-rc-arm64-compatible.apk`，包名com.example.cleannav_mobile，0.2.1 / 2003，arm64-v8a，SHA256 `59881628034379e9f33bad02f9e1f3ed489ca9b9b55d5cf33779dd930d16807e`。

已只读使用指定原Keystore重签，证书SHA256 `7ad7b862a40a3df535f887f0f3477d318469d4efdd8828dfc0dd42d39dbcb893` 与旧Windows Debug完全一致；ZIP对齐/签名验证通过，566项非签名内容与当前RC完全相同，产品源码、原RC包及原密钥未改。

仅离线确认覆盖安装兼容条件；手机安装及实际数据保留仍NOT RUN。未连接手机、未卸载/清数据、未执行Git发布。[本轮报告](R10_B5_PHONE_INSTALL_COMPATIBILITY_RESULT.md)。以下新旧签名差异说明为原RC历史状态，兼容包见本节。

---

## 2026-11-08 Final RC Closure（当前结论）

**OFFLINE_RC_CANDIDATE_READY**：Analyze无问题、Flutter **70/70 PASS**、Python **7/7 PASS**，已在隔离Linux工具链构建并验签arm64-v8a Debug APK。默认C Professional Floorplan、A备用；地图/坐标/目标配置和A7/R9/B3/B4/B5冻结资产保持。

APK：`offline-hardening-final-rc-20261108T132212Z/artifacts/cleannav-mobile-r10-b5-final-rc-arm64-v8a-debug.apk`（82,281,523 bytes），包名com.example.cleannav_mobile，versionName0.2.1，拆分ABI实际versionCode2003（源码+3）。SHA256 `604f712e5a9ce63c67344ed9835955118e63a35fe19e5d577b6f02eec356bb49`。

新Linux Debug证书与旧Windows Debug证书不同，不能直接覆盖旧签名安装；本轮未处理手机安装/数据。手机稳定性、真实强停恢复与实车仍NOT RUN。Token仅会话保存，重启重填；原明文断言已按明确授权改为安全契约，保留Registry/Charger/地图断言。无Release密钥、Git发布、ROS/Gazebo、Gateway业务/Lease/运动。

[最终报告](R10_B5_FINAL_RC_RESULT.md) · [测试矩阵](B5_FINAL_TEST_MATRIX.md) · [SHA256SUMS](SHA256SUMS)。以下旧结论均为历史时间点，不替代本节。

---

# HMI APP 发布候选状态（APP 仓库范围）

此文件仅记录 cleannav-hmi APP；项目根目录 PROJECT_MASTER.md 保持原样，本次授权仅允许修改 release worktree。

## 2026-11-08 Offline Hardening（当前状态，覆盖下方历史验收结论）

本分支新增任务回执持久化/恢复、状态过期、前后台轮询管理、Token 脱敏与会话保存、配置导入回滚、全页 ESTOP 和 Demo 可见性管理。默认 C Professional Floorplan，A 备用；地图和导航资产未变。未改 Gateway、MM、Safety、Lease、导航 API 或车端源码。

**当前不能称为通过全部回归的 Release Candidate。** 旧测试 `test/hmi_contract_test.dart` 要求明文持久化 Token，与本轮会话 Token 行为冲突；原断言保留，没有改成 PASS。以 [本轮完整结果](R10_B5_OFFLINE_HARDENING_RESULT.md) 的最终计数为准。Android Release 和 Debug 在当前 WSL 文件系统上均遭 Gradle 文件缓存 I/O 错误，没有生成本轮新 APK。历史 Debug APK 不包含本轮 Dart 修改，仅作为历史调试基线保留。

正式签名尚未配置；已移除 Release 使用 Debug 密钥的回退，不创建密钥。真机安装、进程被系统杀死后的恢复、后台稳定性与实车均未验证。本轮无 commit/push/tag/PR/merge。


## 事实源

- remote: https://github.com/D1zzyhub7/cleannav-hmi.git
- main/HEAD: 6ddff0f88e200136f2462e42e50aaaccab2d3aa6
- branch: release/r10-b5-professional-map-20261108
- [当前报告](R10_B5_OFFLINE_HARDENING_RESULT.md)、[开发说明](docs/APP_DEVELOPMENT.md)、[操作手册](docs/OPERATIONS_RUNBOOK.md)
- 原始48文件候选、完整diff及新增变更清单保存在本轮忽略的证据目录，未提交、未暂存。
- C/A地图、A7/R9、B3/B4及旧报告均保留历史身份。不得用旧46/46和旧APK替代本轮结果。
