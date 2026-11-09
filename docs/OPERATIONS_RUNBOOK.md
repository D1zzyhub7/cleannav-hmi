## 2026-11-08 Debug 覆盖安装签名兼容（当前交付）

最新兼容包：`offline-hardening-phone-compat-20261108T142237Z/cleannav-mobile-r10-b5-final-rc-arm64-compatible.apk`，包名com.example.cleannav_mobile，0.2.1 / 2003，arm64-v8a，SHA256 `59881628034379e9f33bad02f9e1f3ed489ca9b9b55d5cf33779dd930d16807e`。

已只读使用指定原Keystore重签，证书SHA256 `7ad7b862a40a3df535f887f0f3477d318469d4efdd8828dfc0dd42d39dbcb893` 与旧Windows Debug完全一致；ZIP对齐/签名验证通过，566项非签名内容与当前RC完全相同，产品源码、原RC包及原密钥未改。

仅离线确认覆盖安装兼容条件；手机安装及实际数据保留仍NOT RUN。未连接手机、未卸载/清数据、未执行Git发布。[本轮报告](../R10_B5_PHONE_INSTALL_COMPATIBILITY_RESULT.md)。以下新旧签名差异说明为原RC历史状态，兼容包见本节。

---

## 2026-11-08 Final RC Closure（当前结论）

**OFFLINE_RC_CANDIDATE_READY**：Analyze无问题、Flutter **70/70 PASS**、Python **7/7 PASS**，已在隔离Linux工具链构建并验签arm64-v8a Debug APK。默认C Professional Floorplan、A备用；地图/坐标/目标配置和A7/R9/B3/B4/B5冻结资产保持。

APK：`offline-hardening-final-rc-20261108T132212Z/artifacts/cleannav-mobile-r10-b5-final-rc-arm64-v8a-debug.apk`（82,281,523 bytes），包名com.example.cleannav_mobile，versionName0.2.1，拆分ABI实际versionCode2003（源码+3）。SHA256 `604f712e5a9ce63c67344ed9835955118e63a35fe19e5d577b6f02eec356bb49`。

新Linux Debug证书与旧Windows Debug证书不同，不能直接覆盖旧签名安装；本轮未处理手机安装/数据。手机稳定性、真实强停恢复与实车仍NOT RUN。Token仅会话保存，重启重填；原明文断言已按明确授权改为安全契约，保留Registry/Charger/地图断言。无Release密钥、Git发布、ROS/Gazebo、Gateway业务/Lease/运动。

[最终报告](../R10_B5_FINAL_RC_RESULT.md) · [测试矩阵](../B5_FINAL_TEST_MATRIX.md) · [SHA256SUMS](../SHA256SUMS)。以下旧结论均为历史时间点，不替代本节。

---

# B5 APP 离线操作与后续真机检查

本手册仅覆盖 APP。项目根目录同名 Runbook 未修改，不授权ROS/Gazebo/车辆操作。

1. 使用本发布分支独立 worktree，先查看当前状态与 [结果报告](../R10_B5_OFFLINE_HARDENING_RESULT.md)。不要清理、覆盖原 HMI dirty worktree。
2. 按 [APP_DEVELOPMENT](APP_DEVELOPMENT.md) 执行离线 Mock 测试和7项地图测试；测试失败须如实保留。全量测试中明文Token旧断言尚未与会话Token策略达成一致，当前不宣称全部PASS。
3. 比对 map.png、C SVG、map.json、display metadata 与 SHA256SUMS；不回灌导航地图，不获取实时 OccupancyGrid。
4. Android构建必须在受支持的本地文件系统和正式已配置工具链执行；本轮WSL上的Windows Gradle失败，不搬运源码到授权外目录。正式签名缺失不造钥、不用Debug签名冒充Release。
5. 后续另获手机验证授权后，核验新APK SHA/签名/版本，再安装（本轮未安装）。先用Mock服务验证重启/强停/断网/GET timeout与恢复只GET原status_url，切换页面30次、三个屏幕比例、缩放平移和后台10～15分钟，记录crash/ANR与CPU/RSS。
6. Token重启后重填；不清数据规避未知任务，不自动重新POST。完成或急停终态应清除恢复记录；RESET后不得恢复旧任务。核对Unknown与真实安全状态；软件网络急停不能替代硬件急停。
7. 真实Gateway、STOP/ESTOP/RESET、Task41/43与车辆运动测试需后续明确任务授权，本离线任务不执行。

## 历史

2026-11-08 B5 Finalization：历史46/46、Python7/7、复用旧Debug APK；该结论仅适用于加固前源码，不覆盖本轮新代码。完整历史保留在既有B5报告与docs/B5_RELEASE_NOTES.md。
