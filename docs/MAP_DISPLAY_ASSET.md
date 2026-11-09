# R10-B5 APP 地图显示资产

R10-B5 是 APP 显示版本，默认 **C Professional Floorplan**；**A Faithful Vector** 为保真备用。它不是 SLAM/Nav2/导航算法版本，不能将显示PNG/SVG回灌地图服务器、SLAM、Nav2或Costmap。原始导航地图、Registry、Region/Charger和路线均不变。

## 来源与身份

正式来源：A7 freeze/asset-sha256.json 绑定的 R9 `patrol_pillar_v1_mapping_v1`。原项目路径：`cleannav-experiments/cleannav-patrol-pillar-v1-route-20261102T163219Z/maps/patrol_pillar_v1_mapping_v1/`。本仓库 `map_display/inputs/` 存放三原文件的字节副本，用于独立离线复现；不是导航部署路径。A7原始清单作为来源收据保留，其历史绝对路径只用于追溯；测试按basename查SHA，不访问原开发机绝对路径。

|输入|SHA256|
|---|---|
|map.pgm|`6ffc9e6a249aa6f3504dbd9688b5c84bf35f9fae7d67ea07e53ea5050bad7e76`|
|map.yaml|`1f317300780f08aba52462b45ad1d2457526780cd18a1d29fa63061d7054789f`|
|occupancy_grid.json|`b09fd48018fa0e8b83aa24f66c76d8feec9dc5ab4d79633a2e1ea90743b4410f`|

## 坐标、高清尺寸与覆盖层

- 原格网511×660；resolution准确值`0.05000000074505806 m/cell`（约0.05），origin `[-8.924291610717773, -8.59818172454834, 0.0]`，frame为map。
- 物理范围约25.55×33.00m；不裁剪、不平移、不旋转。PNG2044×2640，displayScale=4；SVG同尺寸，viewBox `0 0 511 660`。
- `assets/map.json`保留原格网物理元数据和目标坐标；`assets/map_display_metadata.json`描述显示比例。不能将原resolution改成1/4再沿用原width/height。
- worldToImage先减origin，逆旋转origin yaw，除resolution，再用原height翻转Y。对dx=x-origin.x、dy=y-origin.y：`u=(cos(yaw)*dx+sin(yaw)*dy)/resolution`，`v=height-(-sin(yaw)*dx+cos(yaw)*dy)/resolution`。
- PNG显示坐标为`(4u,4v)`，再除以显示宽高归一到实际canvas。viewport缩放/平移由底图和动态overlay共用的InteractiveViewer完成，Robot位置/朝向、Region、Charger和目标圈不使用独立变换。背景/覆盖层保留独立RepaintBoundary。
- 车辆位置仍约每2秒采样；Safety/Mission/Gateway原约1Hz single-flight不变；不请求实时OccupancyGrid，不加Timer/API。cacheWidth按viewport×DPR约束高清解码。

## 算法与真实性

`map_display/tools/render_b5.py`、`b4_core.py`均与已验收B5脚本字节相同。仅用已有OpenCV/NumPy/SciPy/Pillow/PyYAML及离线Cairo，不增加APP依赖。

1. 使用原YAML的trinary/negate0/occupied probability>0.65/free<0.25，分别得到occupied/free/unknown；与正式grid逐cell及Y方向核对。
2. 提取精确cell边缘、孔洞和连通组件，不能用像素中心轮廓缩小1pixel薄墙。
3. 用HoughLinesP识别测量线段（未新增RANSAC算法）：rho1cell、theta0.25°、threshold30、minLineLength40cells、maxLineGap2cells。识别线段不等于获得补墙权限。
4. Douglas-Peucker epsilon0.35cell，IoU≥0.96且偏移≤0.5cell；本图202个接受结果只是共线点压缩，4380→1890顶点，native格无变化。
5. 仅在原已知free内做1cell closing，并用Euclidean新增距离限制。34个小片段补入125格，无大范围闭运算，unknown不转free/occupied。
6. 有Hough支持的长墙才拟合（aspect≥15/长度≥2m/RMS≤0.6cell），再检查局部IoU≥0.75/偏移≤1cell。仅一段底部墙通过，8×采样偏移约3.75cm。
7. 圆拟合需圆度≥0.75、径向RMS≤半径10%、角度支持≥330°、实心支持≥85%、半径0.15～0.5m，且IoU≥0.9/偏移≤1cell。本图0/8强制圆化，不完整柱体保留。
8. PNG/SVG几何与原known区域相交，不跨unknown补墙。记录提案/实际裁切后坐标、格数、原区域IoU、偏移和unknown改动。8×亚像素绘制后Lanczos输出4×PNG，SVG保留矢量。

B/C occupied2200→2320，+128/-8格，净增0.3000m²（+5.45%），IoU0.941581；新增距原occupied最大约5cm，unknown mask保持原样。几何边界距离以8×采样，单步6.25mm，不能当作无限精度测量。

原图43.9619% unknown属于正式grid中无有效观测信息，**Unknown不等于Free**。8柱背面、长墙缺口和未知扇区无法靠图像处理恢复；建议未来补扫，不用Gazebo World补全。120个1～2pixel occupied组件可能是噪声也可能是细障碍，未自动删除。

## A/B/C方案

|方案|几何/语义|用途|
|---|---|---|
|A Faithful Vector|原三态完全保留，IoU1.0|保真备用；`map_display/outputs/map_faithful_vector.png`|
|B Conservative Geometry|仅受限、有证据的已知区处理|量化几何候选|
|C Professional Floorplan|与B几何相同，unknown浅蓝灰斜纹/free近白/障碍深色|默认APP `assets/map.png`|

C的分层使未知信息更明确，未伪造完整平面图。A/B/C均为2044×2640 PNG和SVG。A备用PNG与三份SVG纳管；其余指标、审计、比较图由下述命令生成。更换A时只调整显示PNG及对应display metadata，原map.json不改；资产变化后必须另行构建/验收APK。

## 在新开发机复现（Ubuntu22.04或同版WSL）

下列安装是新开发机环境准备说明，本次发布整理没有执行安装。基准版本：OpenCV4.5.4、NumPy1.21.5、SciPy1.8.0、Pillow9.0.1、PyYAML5.4.1、Pycairo1.20.1/Cairo1.16.0；完整apt版本见[APP开发说明](APP_DEVELOPMENT.md)。其他依赖版本可能导致抗锯齿末位差异，不能未经核对宣称相同PNG SHA。

```bash
sudo apt-get update
sudo apt-get install python3-opencv python3-numpy python3-scipy python3-pil python3-yaml python3-cairo fonts-dejavu-core
cd /path/to/cleannav-hmi
sha256sum map_display/inputs/map.pgm map_display/inputs/map.yaml map_display/inputs/occupancy_grid.json
mkdir -p map_display/outputs map_display/comparisons
PYTHONDONTWRITEBYTECODE=1 python3 map_display/tools/render_b5.py --root map_display
PYTHONDONTWRITEBYTECODE=1 python3 map_display/tools/test_b5.py
cmp assets/map.png map_display/outputs/map_professional_floorplan.png
```

生成三种PNG/SVG、原图/墙体/八柱放大/occupied diff、指标和修改审计；没有ROS/Gazebo/World/Registry/Gateway输入。脚本和7项测试未改算法或预期；相同依赖的新隔离发布路径已实际再生并核对PNG/SVG。

## 验证与后续

Flutter3.47.5/Dart3.13.4下执行 `flutter analyze --no-pub`、`flutter test --no-pub`，46项（含128+512随机点、真实paint色点、4种宽高约束、pinch/pan对齐）。Python为上面的7项。详见[发布说明](B5_RELEASE_NOTES.md)。真实手机安装、CPU/RSS/FPS、10～15分钟稳定性、实车都未验证，不能由离线PASS推定。
