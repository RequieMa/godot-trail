extends Control
## 监控器网格 → 单击频道 → 全屏锁定 → ESC/右键返回 的 transition 演示。
##
## 状态机：GRID / TRANSITION_IN / FOCUSED / TRANSITION_OUT。
## 只有在 GRID（可点击进入）与 FOCUSED（可退出）下响应输入；
## TRANSITION_IN / TRANSITION_OUT 期间忽略点击与 ESC，避免过渡中途切换。
## 放大完全由 ZoomCamera 的变换 + FOV 驱动，网格退场只动 modulate.a。

signal focus_changed(new_state: int)

enum FocusState {
	GRID,
	TRANSITION_IN,
	FOCUSED,
	TRANSITION_OUT,
}

## 四个频道在共享 3D 世界中的观察目标（各自立方体中心）。
const CELL_CAMERA_TARGETS: Array[Vector3] = [
	Vector3(-5.0, 0.6, 0.0),
	Vector3(5.0, 0.6, 0.0),
	Vector3(0.0, 0.6, -5.0),
	Vector3(0.0, 0.6, 5.0),
]

## 各频道机位相对目标的偏移，使四个画面构图各不相同。
const CELL_CAMERA_OFFSETS: Array[Vector3] = [
	Vector3(2.0, 1.6, 2.2),
	Vector3(-2.1, 1.4, 2.0),
	Vector3(1.8, 1.9, -2.1),
	Vector3(-1.9, 1.3, -2.3),
]

@export_group("Transition")
## 过渡时长（秒）。
@export var transition_duration: float = 0.45
## 全屏锁定构图的 FOV（越小越贴近画面）。
@export var focus_fov_degrees: float = 28.0
## 锁定构图时相机到目标的距离比例（0.95 = 略微拉近，配合 FOV 收窄）。
@export var focus_distance_scale: float = 0.95
## FOCUSED 时叠加扫描线/暗角。
@export var show_scanline_overlay: bool = true

var state: FocusState = FocusState.GRID
var active_cell_index: int = -1

var _cells: Array[SubViewportContainer] = []
var _cameras: Array[Camera3D] = []
var _source_transform: Transform3D = Transform3D.IDENTITY
var _source_fov: float = 50.0
var _tween: Tween = null

@onready var _monitor_grid: GridContainer = $MonitorGrid
@onready var _transition_layer: Control = $TransitionLayer
@onready var _zoom_view: TextureRect = $TransitionLayer/ZoomView
@onready var _scanline: ColorRect = $TransitionLayer/ScanlineOverlay
@onready var _zoom_viewport: SubViewport = $TransitionLayer/ZoomViewport
@onready var _zoom_camera: Camera3D = $TransitionLayer/ZoomViewport/ZoomCamera
@onready var _back_hint: Label = $BackHint


func _ready() -> void:
	_collect_cells()
	_frame_cell_cameras()
	_setup_zoom_view()
	_set_grid_visuals()
	state = FocusState.GRID
	focus_changed.emit(state)


# --- 运行时查询（供 godot-bridge eval 验证） ---------------------------------

func get_state_name() -> String:
	return str(FocusState.keys()[state])


func get_focus_snapshot() -> Dictionary:
	var target := Vector3.ZERO
	if active_cell_index >= 0 and active_cell_index < CELL_CAMERA_TARGETS.size():
		target = CELL_CAMERA_TARGETS[active_cell_index]
	var camera_position: Vector3 = _zoom_camera.global_position
	return {
		"state": get_state_name(),
		"active_cell": active_cell_index,
		"transition_layer_visible": _transition_layer.visible,
		"transition_layer_alpha": _transition_layer.modulate.a,
		"grid_alpha": _monitor_grid.modulate.a,
		"back_hint_visible": _back_hint.visible,
		"scanline_visible": _scanline.visible,
		"zoom_camera_position": camera_position,
		"focus_target": target,
		"focus_distance": camera_position.distance_to(target),
	}


# --- 初始化 ------------------------------------------------------------------

func _collect_cells() -> void:
	for index in range(CELL_CAMERA_TARGETS.size()):
		var cell := _monitor_grid.get_node("Cell_%02d" % (index + 1)) as SubViewportContainer
		if cell == null:
			push_error("缺少单元格节点 Cell_%02d" % (index + 1))
			continue
		var camera := cell.get_node("SubViewport/Camera3D") as Camera3D
		if camera == null:
			push_error("Cell_%02d 缺少 Camera3D" % (index + 1))
			continue
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.gui_input.connect(_on_cell_gui_input.bind(index))
		_cells.append(cell)
		_cameras.append(camera)


func _frame_cell_cameras() -> void:
	for index in range(_cameras.size()):
		var camera: Camera3D = _cameras[index]
		camera.global_position = CELL_CAMERA_TARGETS[index] + CELL_CAMERA_OFFSETS[index]
		camera.look_at(CELL_CAMERA_TARGETS[index], Vector3.UP)
		camera.fov = _source_fov
		camera.current = true


func _setup_zoom_view() -> void:
	_zoom_viewport.size = get_viewport().size
	_zoom_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_zoom_camera.current = true
	_zoom_camera.fov = _source_fov
	# ViewportTexture 必须在 SubViewport 进入场景树后才取。
	_zoom_view.texture = _zoom_viewport.get_texture()
	if not get_viewport().size_changed.is_connected(_on_window_resized):
		get_viewport().size_changed.connect(_on_window_resized)


func _on_window_resized() -> void:
	_zoom_viewport.size = get_viewport().size


# --- 输入 --------------------------------------------------------------------

func _on_cell_gui_input(event: InputEvent, index: int) -> void:
	if state != FocusState.GRID:
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null and mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
		accept_event()
		_enter_focus(index)


## 根 Control 会吃掉落在空白处的鼠标事件，右键退出必须在这里接。
func _gui_input(event: InputEvent) -> void:
	if state != FocusState.FOCUSED:
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null and mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		_leave_focus()


func _unhandled_input(event: InputEvent) -> void:
	if state != FocusState.FOCUSED:
		return
	var wants_back := false
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		wants_back = true
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null and mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_RIGHT:
		wants_back = true
	if wants_back:
		get_viewport().set_input_as_handled()
		_leave_focus()


# --- 状态机 ------------------------------------------------------------------

## GRID → TRANSITION_IN → FOCUSED
func _enter_focus(index: int) -> void:
	_kill_tween()
	active_cell_index = index
	_source_transform = _cameras[index].global_transform
	_source_fov = _cameras[index].fov

	state = FocusState.TRANSITION_IN
	focus_changed.emit(state)

	_zoom_camera.global_transform = _source_transform
	_zoom_camera.fov = _source_fov
	_transition_layer.visible = true
	_transition_layer.modulate.a = 0.0
	_scanline.visible = false
	_back_hint.visible = false

	var focus_transform := _compute_focus_transform(_source_transform, CELL_CAMERA_TARGETS[index])
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_zoom_camera, "global_transform", focus_transform, transition_duration)
	_tween.tween_property(_zoom_camera, "fov", focus_fov_degrees, transition_duration)
	_tween.tween_property(_monitor_grid, "modulate:a", 0.0, transition_duration)
	_tween.tween_property(_transition_layer, "modulate:a", 1.0, transition_duration)
	_tween.finished.connect(_on_enter_finished, CONNECT_ONE_SHOT)


func _on_enter_finished() -> void:
	if state != FocusState.TRANSITION_IN:
		return
	_set_focused_visuals()
	state = FocusState.FOCUSED
	focus_changed.emit(state)


## FOCUSED → TRANSITION_OUT → GRID
func _leave_focus() -> void:
	_kill_tween()
	state = FocusState.TRANSITION_OUT
	focus_changed.emit(state)
	_scanline.visible = false
	_back_hint.visible = false

	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_zoom_camera, "global_transform", _source_transform, transition_duration)
	_tween.tween_property(_zoom_camera, "fov", _source_fov, transition_duration)
	_tween.tween_property(_monitor_grid, "modulate:a", 1.0, transition_duration)
	_tween.tween_property(_transition_layer, "modulate:a", 0.0, transition_duration)
	_tween.finished.connect(_on_leave_finished, CONNECT_ONE_SHOT)


func _on_leave_finished() -> void:
	if state != FocusState.TRANSITION_OUT:
		return
	_set_grid_visuals()
	state = FocusState.GRID
	focus_changed.emit(state)


## 保持相机朝向不变，沿视线把机位拉近到目标距离的 focus_distance_scale 倍。
func _compute_focus_transform(source: Transform3D, target_point: Vector3) -> Transform3D:
	var distance := source.origin.distance_to(target_point)
	if distance <= 0.001:
		return source
	var direction := (source.origin - target_point) / distance
	var focus_origin := target_point + direction * distance * focus_distance_scale
	return Transform3D(source.basis, focus_origin)


# --- 视觉一致性 --------------------------------------------------------------

func _set_grid_visuals() -> void:
	_transition_layer.visible = false
	_transition_layer.modulate.a = 0.0
	_monitor_grid.modulate.a = 1.0
	_scanline.visible = false
	_back_hint.visible = false
	_set_cells_clickable(true)


func _set_focused_visuals() -> void:
	_transition_layer.visible = true
	_transition_layer.modulate.a = 1.0
	_monitor_grid.modulate.a = 0.0
	_scanline.visible = show_scanline_overlay
	_back_hint.visible = true
	_set_cells_clickable(false)


func _set_cells_clickable(clickable: bool) -> void:
	var filter := Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_IGNORE
	for cell in _cells:
		cell.mouse_filter = filter


## 杀掉进行中的 Tween；若它被中途终止，则按过渡方向收敛到稳定状态，
## 保证 visible / modulate.a / state 三者一致（不允许卡在半透明）。
func _kill_tween() -> void:
	if _tween != null:
		if _tween.is_valid():
			_tween.kill()
		_tween = null
	if state == FocusState.TRANSITION_IN:
		_set_focused_visuals()
		state = FocusState.FOCUSED
		focus_changed.emit(state)
	elif state == FocusState.TRANSITION_OUT:
		_set_grid_visuals()
		state = FocusState.GRID
		focus_changed.emit(state)
