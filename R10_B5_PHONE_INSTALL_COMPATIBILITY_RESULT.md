# R10-B5 Phone Install Compatibility

状态：**DEBUG_SIGNATURE_COMPATIBILITY_VERIFIED**。仅离线签名/包兼容性核验通过，尚未执行手机安装或验证数据保留。

## 交付

- [兼容 APK](offline-hardening-phone-compat-20261108T142237Z/cleannav-mobile-r10-b5-final-rc-arm64-compatible.apk)
- SHA256：`59881628034379e9f33bad02f9e1f3ed489ca9b9b55d5cf33779dd930d16807e`
- 大小：82,331,077 bytes（78.52 MiB）
- 包名：`com.example.cleannav_mobile`
- versionName：`0.2.1`；versionCode：`2003`
- ABI：`arm64-v8a`；debuggable=true。
- [SHA256SUMS](offline-hardening-phone-compat-20261108T142237Z/SHA256SUMS)、[详细验证收据](offline-hardening-phone-compat-20261108T142237Z/verification.json)

## 密钥识别

只读检查用户指定的 `/mnt/c/Users/zzy/.android/debug.keystore`（对应 `C:\Users\zzy\.android\debug.keystore`），未搜索无关磁盘。

keytool确认alias为androiddebugkey、类型PrivateKeyEntry；证书SHA256为：

`7ad7b862a40a3df535f887f0f3477d318469d4efdd8828dfc0dd42d39dbcb893`

与用户指定旧证书完全一致，未凭文件名认定。只读复用既有Android构建配置的默认Debug凭据，通过子进程环境变量传入keytool/apksigner；没有将密码放入命令参数值、日志或报告，没有导出私钥，也没有复制/覆盖原Keystore。原密钥文件前后SHA相等，证据starting-state.json/verification.json。

## 重签方式与校验

未重新编译或修改产品源码。输入为本轮前已验收RC APK，原SHA `604f712e5a9ce63c67344ed9835955118e63a35fe19e5d577b6f02eec356bb49`，原证书b3cb28ed…。

1. 使用现有隔离Linux JDK17/Android build-tools36的zipalign，先4字节ZIP对齐，并对未压缩共享库使用16KiB页对齐。
2. apksigner只读加载匹配的原Debug私钥，对对齐后的副本重签，独立输出用户指定文件名。没有新建密钥，没有伪造或编辑证书。
3. `zipalign -c -P 16 -v 4` 返回0。
4. `apksigner verify --verbose --print-certs` 返回0，证书SHA256与目标逐字节一致。
5. aapt badging返回0，包名/versionName/versionCode/ABI均符合要求。旧B5 Windows APK原versionCode为3，新兼容包为2003。
6. 输入RC与兼容APK的所有ZIP非签名文件名集合一致；**566项逐文件SHA全部一致**，包括Dart代码、AndroidManifest、资源、原有Registry/地图/目标配置。只排除标准META-INF签名文件；没有笼统排除整个META-INF。APK v2/v3签名块和ZIP对齐填充属于签名/容器变化。
7. 原RC APK、原Keystore、全部既有产品源码与资产保持本轮起点内容；没有重复运行与纯重签无关的Flutter/Python测试，原70/70、7/7和Analyze0是沿用的不变产品验证记录，不伪造成本轮新执行。

完整命令调用与脱敏后的日志保存在 `offline-hardening-phone-compat-20261108T142237Z/`，脚本sign_compatible.py不包含密码值/私钥。`intermediate/aligned-input.apk`仅为重签中间文件，不是交付安装包。

|校验|结果|证据|
|---|---|---|
|旧Keystore证书及PrivateKeyEntry|PASS|certificate.json|
|兼容包证书|PASS，与目标7ad7b862…一致|signature-check.log|
|ZIP/16KiB对齐|PASS|zipalign-check.log|
|package/version/ABI|PASS，com.example.cleannav_mobile /0.2.1/2003/arm64-v8a|badging.log、verification.json|
|全部非签名Payload|PASS，566/566完全一致|payload-sha256.json|
|地图/Registry/目标|PASS，随全部payload及4项asset逐字节核验|verification.json|
|原RC/原密钥/源码保护|PASS|verification.json、source-preservation.json|
|SHA256SUMS|实际核验PASS|checksum-check.log|
|手机保留数据覆盖安装|NOT RUN|本轮不连接手机、不执行adb install|

## 后续与范围

签名、包名、版本码和ABI已满足目标旧证书安装环境的离线更新兼容条件，可用于后续用户安排的保留数据覆盖安装验证。**不能声称已经在红米上安装成功或确认保留数据**；手机当前实际安装包身份、Android安装策略、运行稳定性仍须届时验证。不要为安装问题擅自卸载、清数据或改用假证书。

未连接手机、未执行ADB命令、未启动/停止ROS/Gazebo、未发送Gateway业务请求、未获取Lease或车辆运动，无Git commit/push/tag/PR/merge。分支/HEAD/index保持；新APK和中间文件都在已有Git忽略目录中，原密钥仍留在指定安全位置，不进入提交。

仅在APP README、APP作用域PROJECT_MASTER和Runbook补充本轮当前交付指针，历史RC报告/原APK保留。旧“Linux新证书不同”结论仍正确描述原RC包，新兼容APK已解决本轮指定的旧证书兼容问题。

新建集成终端0，无手工后台任务；工具托管签名进程已完成，无自己的Java/签名任务残留。Shared Memory updated: cleannav_next_actions、cleannav_validation_status、cleannav_session_20261108_r10_b5_phone_install_compatibility。
