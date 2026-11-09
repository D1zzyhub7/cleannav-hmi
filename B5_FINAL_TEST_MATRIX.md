# B5 Final Test Matrix

**OFFLINE_RC_CANDIDATE_READY**。完整Flutter70/70，Python7/7，analyze0；native Debug构建0、签名/ABI/资产核验通过。均为离线Mock；不包含手机/实车验证。

|验收项|覆盖/证据|结果|
|---|---|---|
|Token五项安全契约|hmi_contract_test原测试保留Registry/Charger/map断言，补Token内存、Authorization、重建、错误与日志|PASS|
|Task41/43原回执恢复|offline_hardening_test/原hmi_contract，序列化重建、原status_url、无第二次POST|PASS|
|响应丢失/POST timeout/202|HTTP契约+新增final_rc_ui五场景；UNKNOWN/ACCEPTED，非SUCCEEDED|PASS|
|GET timeout/暂不可用|保留原身份，恢复后继续GET，原GETsingle-flight|PASS|
|无法恢复身份|损坏回执保留，人工核对提示，导航POST为0|PASS|
|终态清理|SUCCEEDED/CANCELED/EMERGENCY_STOPPED及FAILED/REJECTED停止追踪|PASS|
|Safety/ESTOP/RESET|1.0/1.1聚合状态、过期UNKNOWN、急停阻止导航、无自动RESET/旧任务恢复|PASS|
|错误导入/生命周期/布局|原配置不被破坏、前后台/页退出、3尺寸/30次页切换|PASS|
|地图投影|512+128随机点、车辆/Region/Charger/Target、缩放和平移|PASS|
|完整Flutter|flutter test --no-pub --concurrency=1，70/70|PASS|
|Python地图|unittest discover map_display/tools test_b5.py，7/7|PASS|
|Analyze|flutter analyze --no-pub，无问题|PASS|
|APK|com.example.cleannav_mobile /0.2.1/2003，arm64-v8a，min24/target36，debuggable，签名通过|PASS|
|APK地图/目标|4资产逐字节一致；displayScale4与原坐标一致|PASS|
|冻结保护|B3 203/B4 242/B5原APP148/A7R9 30；合计623|PASS|
|APK签名覆盖旧安装|新旧Debug证书不同，不可直接覆盖旧签名安装|KNOWN LIMIT|
|手机/实车|未安装、不连接Gateway/ROS/Gazebo/Lease/车辆运动|NOT RUN|

APK SHA256 `604f712e5a9ce63c67344ed9835955118e63a35fe19e5d577b6f02eec356bb49`。原始日志、cwd/argv、rc、工具链与资产收据见 [offline-hardening-final-rc-20261108T132212Z](offline-hardening-final-rc-20261108T132212Z)；详见 [最终报告](R10_B5_FINAL_RC_RESULT.md)。
