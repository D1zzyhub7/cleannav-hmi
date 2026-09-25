# CleanNav M1 Competition APP

Flutter Phone APP for the CleanNav Competition HIL runtime. The APP sends only
upper-level task requests through the PC HMI Gateway; it does not publish ROS2
topics, `/cmd_vel`, or Ackermann parameters.

## Runtime architecture

```text
Phone Flutter APP
    -> PC / WSL HMI Gateway :18082
    -> J6 HTTP HIL :18081
    -> J6 Mission Manager
    -> PC Navigation HIL
```

The APP does not send `source`. The Gateway forces `source=APP` when forwarding
the request to J6.

## HTTP API

The connection page accepts the current PC LAN address in this form:

```text
http://<PC current LAN IP>:18082
```

The IP address is intentionally not hard-coded because the hotspot address can
change.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/state` | Gateway, J6, robot and TaskStatus state |
| GET | `/api/map` | RTAB OccupancyGrid and robot pose |
| POST | `/api/tasks` | Submit an upper-level task |
| POST | `/api/emergency-reset` | Reset emergency stop after confirmation |

The APP keeps these states separate:

- `Gateway connected`: `/api/state` returned HTTP 200;
- `J6 connected`: top-level `j6_connected` is true;
- `TaskStatus present`: locally inferred from execution/command ID, task ID,
  or a non-`UNKNOWN` task state.

## Competition task

The M1 competition task page exposes only:

```text
task_id: 30
key: CLEAN_NEAREST_LEAF
中文：清扫最近落叶
```

The request contains a unique `command_id`, `task_id`, timestamp, validity
period and optional confirmation. It does not contain `source`.

## Real map

`GET /api/map` is rendered as a real OccupancyGrid:

- unknown cells are gray;
- free cells are white;
- occupied cells are dark gray/black;
- ROS map rows are vertically flipped for screen coordinates;
- origin, resolution and yaw are used for robot pose conversion;
- the robot pose and heading are shown when available.

No simulated route, target, or robot trajectory is rendered when the map is
unavailable.

## Android network requirement

Android keeps `INTERNET` permission and
`android:usesCleartextTraffic="true"` for the local-network HTTP HIL path.

## Build

After installing Flutter, regenerate dependencies and generated platform files:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

No build artifacts or commits are part of the M1 source change.
