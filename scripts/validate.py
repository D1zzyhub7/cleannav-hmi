#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
required = [
    "pubspec.yaml", "lib/main.dart", "lib/controllers/app_controller.dart",
    "lib/services/demo_transport.dart", "lib/services/http_transport.dart",
    "lib/services/ble_transport.dart", "lib/widgets/mission_map.dart",
    "lib/screens/overview_page.dart", "lib/screens/tasks_page.dart",
    "lib/screens/connection_page.dart", "scripts/bootstrap.ps1", "README.md",
]
missing = [item for item in required if not (root / item).exists()]
assert not missing, f"缺少文件: {missing}"

catalog = (root / "lib/models/task_definition.dart").read_text(encoding="utf-8")
ids = [int(value) for value in re.findall(r"TaskDefinition\(id: (\d+)", catalog)]
assert ids == [1, 2, 3, 4, 5, 6, 7, 10, 20, 30, 31, 32, 33], ids

routes = dict((int(task), route) for task, route in re.findall(r"id: (\d+).*?route: RouteKind\.(\w+)", catalog))
for task_id in (5, 10, 20, 30, 31, 32, 33):
    assert task_id in routes, task_id
assert len({routes[5], routes[10], routes[20], routes[30], routes[31], routes[32], routes[33]}) == 7

demo = (root / "lib/services/demo_transport.dart").read_text(encoding="utf-8")
for phrase in ("清扫机构关闭", "局部回旋", "扩大覆盖", "积水边缘", "返航路线"):
    assert phrase in demo, phrase

ble = (root / "lib/services/ble_transport.dart").read_text(encoding="utf-8")
assert "interface_version': '1.0'" in ble
assert "safety_confirmed" in ble

print(f"CleanNav Mobile 校验通过：{len(required)} 个核心文件，{len(ids)} 个冻结任务，7 套差异化路线。")
