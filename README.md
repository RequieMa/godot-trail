# Godot Trail

Godot 4.7 的「2D UI 承载 3D SubViewport」演示项目：监控器网格、全屏锁定过渡、剧院平面地图与 9 路监控墙。当前为 **占位美术阶段**，重点在结构、过渡手感与数据驱动的地图/机位。

---

## 环境

| 项 | 值 |
|---|---|
| 引擎 | Godot 4.7.x（开发验证于 4.7.2 stable） |
| 语言 | GDScript（本项目不含 C#） |
| 渲染 | Forward+ |
| 平台 | 桌面（Windows 验证） |

## 快速开始

用 Godot 打开本目录（含 `project.godot`）即可。命令行方式：

```bash
# 运行 9 路监控墙
godot --path . scenes/theater_monitor.tscn

# 运行剧院平面图（俯视）
godot --path . scenes/theater_map.tscn

# 运行 4 路网格演示
godot --path . scenes/monitor_grid_demo.tscn

# 冒烟测试（无窗口）
godot --headless --path . --script tests/smoke_test.gd

# 无窗口跑场景 40 帧（检查脚本是否报错）
godot --headless --path . --quit-after 40 scenes/theater_monitor.tscn
```

> 所有路径均为相对项目根的路径；仓库内不保存任何机器相关的绝对路径。

## 场景一览

| 场景 | 内容 | 交互 |
|---|---|---|
| `scenes/main.tscn` | 最小基线（打印就绪标记） | 无 |
| `scenes/monitor_grid_demo.tscn` | 4 个 SubViewport 立方体网格 + 全屏锁定过渡 | 点击格子进入；`ESC` / 右键返回 |
| `scenes/theater_map.tscn` | 剧院俯视平面占位图：9 房间、通道/堵死、C1–C9 机位 | 无（用于检查布局与机位） |
| `scenes/theater_monitor.tscn` | 9 路 3×3 监控墙（数据来自剧院地图） | 点击某一路全屏；`ESC` / 右键返回 |

### 剧院平面（theater_map）

```
楼梯 ── 大厅 ── 观众席 ── 舞台 ── 后台
          │        │                   │
        正门(堵死) 走廊 ── 道具仓      侧门(出口)
```

- 单位：米（`1 unit = 1 m`），x 向东、z 向南、y 向上
- 9 个房间：楼梯、走廊、道具仓（盲区）、大厅（锚点 A）、观众席、舞台（起火点）、后台（锚点 B）、正门（堵死）、侧门
- 9 个机位：C1 大厅、C2 观众席、C3 舞台、C4 走廊、C5 道具仓门口、C6 后台、C7 侧门、C8 楼梯、C9 正门
- 房间/通道/机位全部由 `ROOMS` / `LINKS` / `CAMERAS` 三张常量表驱动，改布局只改表

### 监控墙（theater_monitor）

- 每路一个 `SubViewport`（共享同一 3D 世界，复制地图机位的变换）
- 3×3 网格，格子 16:9，居中排布
- 点击 → 全屏层淡入 + `ZoomCamera` 从机位后撤 2 m 推近 → `FOCUSED`，叠加扫描线/暗角
- `ESC` / 右键 → 反向过渡回到网格
- 过渡期间（`TRANSITION_IN` / `TRANSITION_OUT`）屏蔽所有输入，避免中途切换

状态机：

```
GRID ──点击──▶ TRANSITION_IN ──完成──▶ FOCUSED
 ▲                                      │
 └────────── GRID ◀──完成── TRANSITION_OUT ◀──ESC/右键
```

## 目录结构

```
project.godot
scenes/
  main.tscn                  # 基线
  monitor_grid_demo.tscn     # 4 路网格演示
  theater_map.tscn           # 剧院平面图
  theater_monitor.tscn       # 9 路监控墙
scripts/
  main.gd
  monitor_grid_demo.gd       # 4 路网格控制器
  theater_map.gd             # 地图构建器（房间/通道/机位/道具）
  theater_monitor.gd         # 9 路监控墙控制器
shaders/
  grid_ground.gdshader       # 地面网格
  scanline_vignette.gdshader # 扫描线 + 暗角
tests/
  smoke_test.gd              # 冒烟测试
manifests/asset_manifest.json
external-assets/             # 大体积资源目录（内容不入库）
docs/screenshots/            # README 用截图
```

> `autoload/mcp_interaction_server.gd` 不在此列：它由 godot-bridge 在本机调试时自动注入，带本地 eval 能力，已加入 `.gitignore`。

## 常用 API

`theater_map.gd`（挂在 `theater_map.tscn` 根节点）：

| 方法 | 返回 |
|---|---|
| `get_camera_nodes()` | `{ "C1": Node3D, ... }` 机位挂点（子节点 `Camera3D` 提供变换） |
| `get_map_summary()` | 房间数、机位列表（id / 房间 / 位置 / fov）、盲区房间、平面尺寸 |
| `get_room_names()` | 房间 id 列表 |
| `get_room_display_name(room_id)` | 房间中文名 |

`theater_monitor.gd` / `monitor_grid_demo.gd`（挂在各自根节点）：

| 方法 | 返回 |
|---|---|
| `get_state_name()` | `"GRID"` / `"TRANSITION_IN"` / `"FOCUSED"` / `"TRANSITION_OUT"` |
| `get_focus_snapshot()` | 当前状态、激活机位、图层可见性/alpha、相机位置与 fov 等 |

信号：`focus_changed(new_state: int)`。

## 可调参数

`theater_monitor.gd`：

| 参数 | 默认 | 说明 |
|---|---|---|
| `transition_duration` | 0.45 | 过渡时长（秒） |
| `transition_pull_back` | 2.0 | 进场时机位后撤距离（米） |
| `transition_fov_widen` | 1.08 | 进场起始 FOV 倍数 |
| `show_scanline_overlay` | true | FOCUSED 时叠加扫描线/暗角 |

`theater_map.gd`：`CAMERA_HEIGHT`（机位高度）、`WALL_HEIGHT`（墙高）、`CEILING_LAYER`（天花板渲染层）。

## 测试

`tests/smoke_test.gd` 校验 `application/run/main_scene` 已配置、可加载、可实例化，退出码 0/1：

```bash
godot --headless --path . --script tests/smoke_test.gd   # 期望输出 SMOKE_TEST_PASS
```

## 资产

- 大体积资源放 `external-assets/`，内容不纳入版本库（见 `.gdignore` 与 `.gitignore`）
- 资产清单：`manifests/asset_manifest.json`

## 截图

![9 路 3×3 监控墙](docs/screenshots/monitor9_wall.png)

![点击某一路全屏](docs/screenshots/monitor9_focus.png)

![剧院平面与 C1–C9 机位](docs/screenshots/theater_map.png)

## 已知限制

- 美术全部为占位方盒，无贴图/材质细节
- `theater_map` / `theater_monitor` 的节点由脚本在运行时生成，编辑器里需运行后才能看到完整结构
- 地图与监控墙之间目前是「复制机位变换」，尚未做真正的画面串流/录制
- 调试用的 `autoload/mcp_interaction_server.gd` 不入库（带本地 eval，公开仓库不应携带）；用 godot-bridge 跑一次项目会临时注入

更多踩坑记录与约定见 [MEMORY.md](MEMORY.md)。
