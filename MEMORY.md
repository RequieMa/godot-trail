# MEMORY — 踩坑与经验

记录本项目开发过程中真实踩到的坑、定位方式和约定。**新接手先读这一篇，再读 README。**

---

## 0. 约定速查

| 约定 | 说明 |
|---|---|
| 路径 | 仓库内一律用相对于项目根的路径或 `res://`；不写机器绝对路径 |
| 注释 | 中文，说明「为什么」而不是「做了什么」 |
| 地图数据 | 房间/通道/机位写在 `theater_map.gd` 的常量表里，不要手改节点 |
| 验证 | 先 `validate` → 再 headless 冒烟 → 最后交互验证（三者缺一不可） |
| 工具状态 | `.dsh/`（Game Studio 状态、日志、截图）属于本机工具产物，不入库 |

---

## 1. 工具链（DSH Game Studio + godot-bridge）

### 1.1 `game_studio_engine` 的日志抓手不完整

`engine build / test / run` 返回的 **exitCode 可信**（用不存在的脚本探针验证过：exit 1），但日志里的 `STDOUT:` / `STDERR:` 段始终为空——哪怕 Godot 明明打印了内容。

**后果**：任何「日志里必须出现 XXX 标记」的验收都会误判失败。

**做法**：断言输出一律用 `godot_*` 桥接工具（`godot_run_headless` 能拿到完整 stdout/stderr），`engine` 只用来确认退出码和拿 `logPath`。

### 1.2 引擎可执行文件找不到

`game_studio_engine` 报「未找到 Godot 可执行文件」，而 `godot_*` 工具跑得好好的：两者读的不是同一份配置（`engine` 找 PATH / `GODOT_BIN`，bridge 用插件里的路径设置）。

**做法**：不要因为 `engine build` 失败就以为环境坏了；先确认 `godot_*` 能否运行。给 `engine` 配环境变量是可选项，不是必须。

### 1.3 `game_studio_dispatch` 不可用

调用直接返回「subagents 服务或 parent agent 不可用」。排查无果（插件注入缺失，非项目问题）。

**做法**：任务在主 agent 内直接实施；`route` 的选型/技能建议仍然有价值，可以照着做。

### 1.4 `game_studio_gate` 的三个前置条件

1. 必须有 `active-task.json`，否则返回 `No active task for Gate execution.`
2. 任务里必须有 `scope`，否则 `scope-clean` 判为 `SKIP`（不是 PASS），`allPass` 为 false
3. `scope-clean` 拿 git 工作区跟 scope 比对，**工具自己写入的文件也算越界**

**做法**：写任务时把这三类都放进 scope——本轮改的源码、`.dsh/`、`project.godot`、`autoload/`。每次 `write-task` 都要带完整 `contract`（含 scope），否则下一次 gate 会丢上下文。

### 1.5 `godot_command click` 的按键参数必须是数字

传 `{"button":"left"}` 会得到 `button_index=0 (MouseButton.NONE)`：事件能到达 `gui_input`，但永远匹配不上 `MOUSE_BUTTON_LEFT`，表现为「点了完全没反应」，且只在日志里留下一句 `Condition "button == MouseButton::NONE" is true`。

**做法**：`1` = 左键，`2` = 右键。键盘用 `{"key":"Escape"}` 正常。

### 1.6 截图别用 `godot_screenshot` 的返回值

它把整张 PNG 以 base64 塞进返回 JSON，一张 1152×648 的图就是二十多万字符，直接撑爆上下文。

**做法**：在 `eval` 里自己落盘再读文件：

```gdscript
var img := get_tree().root.get_texture().get_image()
img.save_png(OS.get_user_data_dir() + "/shot.png")
```

`user://` 的实际目录因机器而异，用 `OS.get_user_data_dir()` 拼接即可，不要硬编码。

### 1.7 不要在 shell 里直接跑 godot

用 shell 启动 Godot 会因文件沙箱拦截 `user://` 写入而段错误。始终走 `godot_run_project` / `godot_run_headless` / `godot_headless_op`。

### 1.8 bridge 会自动改 `project.godot`

首次 `godot_run_project` 会往 `project.godot` 注入 `[autoload] McpInteractionServer`，并在 `autoload/` 落一个脚本（带本地 eval 能力的交互服务器）。这不是手改，git diff 里看到别惊讶——所以 `.gitignore` 里忽略 `autoload/`，提交前把 `project.godot` 的 `[autoload]` 段清掉即可。

另外验证期间同时开第二个实例会报 `Failed to listen on port 9090`——无害，不影响功能。

---

## 2. Godot 具体坑

### 2.1 没有 main_scene 就跑不起来

`project.godot` 里没设 `application/run/main_scene` 时，`godot --headless` 直接报 `Can't run project: no main scene defined`，连测试都跑不了。初始化项目第一步就该设好。

### 2.2 `SubViewportContainer` 会吞掉输入

它把鼠标事件转发进 SubViewport，自身 `gui_input` 表现不可靠（实测点击无效）。

**做法**：外层用普通 `Control` 包裹负责点击，`SubViewportContainer` 设 `mouse_filter = IGNORE`：

```
Cell (Control, MOUSE_FILTER_STOP, gui_input 连接)
└── View (SubViewportContainer, MOUSE_FILTER_IGNORE, stretch = true)
    └── SubViewport
        └── Camera3D
```

### 2.3 根 Control 会吃掉「空白处」的鼠标事件

full-rect 的根 `Control` 默认 `MOUSE_FILTER_STOP`，落在它身上的点击被 GUI 消费，`_unhandled_input` **收不到**——表现为右键退出失效（左键点格子因为有子节点，反而正常）。

**做法**：全局鼠标类交互写在根节点的 `_gui_input`；`_unhandled_input` 只用来兜键盘。两个 demo（`monitor_grid_demo.gd` / `theater_monitor.gd`）都踩过这个坑。

### 2.4 `Camera3D` 没有 `origin` / `basis` 属性

`Camera3D`（Node3D）只有 `transform` / `global_transform`。写 `camera.origin` 或 `camera.basis` 会运行时报 `Invalid access to property or key`，而且只在点击那一刻炸出来。

**做法**：先取 `var t := camera.global_transform`，再用 `t.origin` / `t.basis`。

### 2.5 `ViewportTexture` 的时机

`SubViewport.get_texture()` 必须在 SubViewport 已进入场景树之后调用，否则拿不到有效纹理。放在 `_ready()` 里做最稳。

### 2.6 `stretch = true` 会改写 SubViewport 尺寸

标了 `stretch=true` 的 `SubViewportContainer` 会在布局阶段把子 `SubViewport.size` 改成自己的尺寸——scene 文件里写的 `640×360` 只是设计值，运行时会变。

**记法**：`stretch=true` = 「画面拉伸铺满容器，视口分辨率跟随容器」。

### 2.7 多个 SubViewport 可以共享同一个 3D 世界

`SubViewport.own_world_3d` 默认 `false`，即使用父视口的 `World3D`。所以监控墙可以：地图放一份 3D 场景，9 个 SubViewport 各放一台 `Camera3D` 复制地图机位变换，就能看到 9 个不同视角——不需要复制 9 份场景。

注意 root viewport 里必须**没有** current 相机，否则 3D 世界会盖在 UI 上（监控墙里把地图自带的俯视相机 `current = false`）。

### 2.8 室内有「天花板」又不挡俯视图：用渲染层

直接加天花板会让俯视地图被盖住。做法：

- 天花板 `MeshInstance3D.layers = 2`（第 2 渲染层）
- 俯视相机 `cull_mask = 1`（只渲染第 1 层）
- 室内机位用默认 `cull_mask`（全层）→ 能看到天花板

### 2.9 `class_name` 在 `--script` 校验里可能不可见

给 `theater_map.gd` 加 `class_name TheaterMap` 后，用 `godot_validate_script` 校验引用它的脚本会报 `Could not find type "TheaterMap"`——因为全局类名缓存（`global_script_class_cache.cfg`）是编辑器/导入阶段生成的，独立 headless 脚本校验时还没有。

**做法**：跨脚本调用改用无类型变量 + 动态调用（`@onready var _map = $TheaterMap`），或者干脆不依赖 `class_name`。

### 2.10 `.uid` 文件要入库

Godot 4.4+ 会给每个脚本生成同名 `.uid`（`uid://xxxx`）。它是资源引用稳定性的一部分，应随源码提交；否则每次换机器/CI 首次导入都会产生 diff 噪音。

### 2.11 headless 跑场景必须限帧

`godot --headless --path . scenes/xxx.tscn` 不退出，会被超时杀掉。加 `--quit-after N`（或让脚本自己 `quit()`），一般 30–40 帧足够暴露 `_ready`/首帧错误。

### 2.12 Tween 中断必须收敛状态

过渡中被 kill 的 Tween 不会发 `finished`，容易留下「画面半透明但状态已变」。做法是 `_kill_tween()` 里按当前方向强制收敛：

- `TRANSITION_IN` 被打断 → 直接置为 `FOCUSED` + 聚焦视觉
- `TRANSITION_OUT` 被打断 → 直接置为 `GRID` + 网格视觉

并且过渡期间用状态机 guard 屏蔽输入，避免中途再次触发。

### 2.13 监控墙「好看」的几个数值

- 3×3 比 4×2 更好看：每路更大、辨识度更高（格子 `340×191`，间距 10，`CenterContainer` 居中）
- 机位高度要**低于**墙高（`2.1 < 2.4`）才有室内摄像头感；高于墙顶会拍出「越墙俯视」的奇怪构图
- 相机 `look_at` 的目标用地面高度（`y = 0`）而不是房间中心，俯角更大、画面里地板/道具更多，墙面更少

---

## 3. 工作流经验

1. **改完就重启实例**：`godot_stop_project` → `godot_run_project`。运行中改脚本不会热更新，容易误判「改了没效果」。
2. **验证顺序**：`godot_validate_script`（语法）→ `godot_run_headless --quit-after`（`_ready` 崩溃）→ 交互（点击/按键/状态）。三层各自能抓到不同类型的问题，跳过哪层都会返工。
3. **留证据三件套**：状态快照（`get_focus_snapshot()`）+ 截图 + 退出码。只截图的验证没法证明状态机对，只 eval 的验证没法证明画面对。
4. **状态机先写 guard 再写效果**：先保证「什么状态下允许什么输入」，再调 tween，能省掉大部分「中途乱切」的 bug。
5. **占位阶段优先数据驱动**：地图/机位用表驱动，改布局是改几行数据；一旦把坐标写死在节点里，调一次要重启一次编辑器。
6. **工具报错先分清归属**：dispatch/gate/engine 的问题先看作是工具链问题（有明确报错特征），不要一头钻进游戏代码里找不存在的 bug。

---

## 4. 配置化与数据驱动

### 4.1 元数据进资源文件，运行时状态留内存

`ClueManager` 最初把 `clue_id` 和取值硬写在业务脚本里（`door_code_A / "A-317"`），改一条线索就要改代码。现在拆成两层：

- **定义表**（`resources/data/clues.json`）：`id` / `value` / `title` / `source` / `description` / `unlocks` / `action`
- **运行时状态**（`ClueManager` 内存 `Dictionary`）：只有「玩家是否已登记」

`register_clue(id)` 不传值时从定义表取默认值；`build_action_text(id)` 用 JSON 里的 `action` 模板（`{value}` 占位）生成 UI 文案。demo 里改了 JSON 的 `value` 再点「重新加载」按钮，按钮文案立即跟着变——不需要改任何 `.gd`。

**判断标准**：出现「策划要调数值/文案」的需求时，先想数据文件；出现「玩家进度/存档状态」时才放内存。

### 4.2 JSON 读取要留兜底

`FileAccess` 直读在编辑器/开发运行时没问题，导出后裸文件可能不可用。做法：

```gdscript
func _read_json(path: String) -> Variant:
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path)
		if not text.is_empty():
			return JSON.parse_string(text)
	if ResourceLoader.exists(path):
		var resource = load(path)
		if resource is JSON:
			return (resource as JSON).data
	return null
```

解析失败不要静默：发 `definition_error` 信号，demo 里直接把错误显示在界面上。

### 4.3 文本文件只能用编辑工具改

用 PowerShell 的 `Get-Content`/`Set-Content` 批量替换 `.gd` 里的中文，会把 UTF-8 内容按 ANSI 读进来再写出去，**整份文件中文变乱码、换行也会丢**。改代码/文档一律用编辑工具或写文件，不要用 shell 做文本替换。

---

## 5. 历史问题清单（已解决）

| 问题 | 根因 | 修复 |
|---|---|---|
| 项目无法启动 | `project.godot` 缺 `run/main_scene` | 设置主场景 + 冒烟测试 |
| 点击格子无反应 | `godot_command click` 传了字符串按钮名 | 传数字 `1` |
| 首次点监控格报 `Invalid access to property 'origin'` | 在 `Camera3D` 上取 `.origin` | 改用 `_source_transform.origin` |
| 右键无法退出全屏 | 根 Control 消费了事件 | 补根节点 `_gui_input` |
| 监控画面顶部黑色空洞 | 房间无天花板 | 天花板放渲染层 2 + 俯视相机裁剪 |
| 「堵死」标记画了两遍 | 房间侧和连接处各画一次 | 只在连接处画 |
| gate 的 scope-clean 反复 FAIL | `.dsh/`、`project.godot`、`autoload/` 未纳入 scope | 写任务时纳入 scope |
| 监控墙 4×2 显得松散 | 格子过小、比例失衡 | 改 9 路 3×3 |
| HBox 里的 Label 竖着一字一列 | Label 最小宽度被压到 0，autowrap 生效 | `size_flags_horizontal = EXPAND_FILL` |
| 截图拿到上一帧（数值不更新） | 改完 UI 立刻抓纹理 | `await get_tree().process_frame` ×2 再截图 |
| `get_demo_state()` 返回 `{}` | `(child as Button)` 对 Label 返回 null，再取 `.text` 报错 | 先 `if child is Button` 判断 |
| `:=` 无法推断类型 | 变量来自无类型 Variant（字典/autoload 动态调用） | 显式标注类型 |
| 改完脚本没生效 | 复用了旧实例（旧代码仍在跑） | 改完必须重启；9090 被占时用 `port=9091` 起新实例，不要杀外部实例 |

---

## 6. 待办 / 已知限制

- 地图与监控墙还没有真正的「画面串流」，目前是复制机位变换
- 监控 UI 没有编号角标、时间戳、录像状态等监控质感元素
- 占位美术无贴图；房间内容仅方盒
- 磁带 `stream` 字段还没接真实视频，仅用事件时间轴驱动
- `TimeManager` 的默认救援时间轴仍写死在脚本常量里，可考虑同样挪到 JSON
- `autoload/mcp_interaction_server.gd` 属于调试设施，发行前需移除
