extends Control
## 剧院 8 路监控墙：网格显示 C1–C8 画面，点击某路 → 全屏锁定，ESC / 右键退出。
##
## 与 monitor_grid_demo 同一套方案：每路一个 SubViewport 渲染共享 World3D，
## 全屏由 ZoomViewport 的 Camera3D 平移 + 交叉淡化完成，网格退场只动 modulate.a。
## 状态机：GRID / TRANSITION_IN / FOCUSED / TRANSITION_OUT。

signal focus_changed(new_state: int)

enum FocusState {
	GRID,
	TRANSITION_IN,
	FOCUSED,
	TRANSITION_OUT,
}

const VIEWPORT_SIZE := Vector2i(640, 360)

@export_group("Transition")
## 过渡时长（秒）。
@export var transition_duration: float = 0.45
## 进场时机位沿视线后撤的距离（米），形成“推近”感。
@export var transition_pull_back: float = 2.0
## 进场起始 FOV 放大倍数（略宽 → 收到该摄像头原本构图）。
@export var transition_fov_widen: float = 1.08
## FOCUSED 时叠加扫描线/暗角。
@export var show_scanline_overlay: bool = true

var state: FocusState = FocusState.GRID
var active_cell_index: int = -1

var _cells: Array[Dictionary] = []
var _tween: Tween = null
var _focus_start_transform: Transform3D = Transform3D.IDENTITY
var _focus_start_fov: float = 70.0
var _source_transform: Transform3D = Transform3D.IDENTITY
var _source_fov: float = 70.0

# 地图脚本自定义方法通过动态调用访问（不强依赖全局类名缓存）。
@onready var _map = $TheaterMap
@onready var _monitor_grid: GridContainer = $MonitorWall/Center/Grid
@onready var _transition_layer: Control = $TransitionLayer
@onready var _zoom_view: TextureRect = $TransitionLayer/ZoomView
@onready var _scanline: ColorRect = $TransitionLayer/ScanlineOverlay
@onready var _zoom_viewport: SubViewport = $TransitionLayer/ZoomViewport
@onready var _zoom_camera: Camera3D = $TransitionLayer/ZoomViewport/ZoomCamera
@onready var _back_hint: Label = $BackHint


func _ready() -> void:
	_disable_map_overview()
	_hide_map_labels()
	_build_cells()
	_setup_zoom_view()
	_set_grid_visuals()
	state = FocusState.GRID
	focus_changed.emit(state)


# --- 运行时查询（供 godot-bridge eval 验证） ---------------------------------

func get_state_name() -> String:
	return str(FocusState.keys()[state])


func get_focus_snapshot() -> Dictionary:
	var camera_id := ""
	if active_cell_index >= 0 and active_cell_index < _cells.size():
		camera_id = String(_cells[active_cell_index].id)
	return {
		"state": get_state_name(),
		"cells": _cells.size(),
		"active_cell_index": active_cell_index,
		"active_camera": camera_id,
		"transition_layer_visible": _transition_layer.visible,
		"transition_layer_alpha": _transition_layer.modulate.a,
		"grid_alpha": _monitor_grid.modulate.a,
		"back_hint_visible": _back_hint.visible,
		"scanline_visible": _scanline.visible,
		"zoom_camera_position": _zoom_camera.global_position,
		"source_position": _source_transform.origin,
		"source_fov": _source_fov,
		"zoom_fov": _zoom_camera.fov,
	}


# --- 初始化 ------------------------------------------------------------------

## 地图自带的俯视相机在监控场景里不需要（3D 只通过各路 SubViewport 呈现）。
func _disable_map_overview() -> void:
	var overview := _map.get_node_or_null("OverviewCamera") as Camera3D
	if overview != null:
		overview.current = false


## 关掉地图上的 Label3D 与摄像头挂点标记，避免每路画面里糊满房间名/青色方块。
func _hide_map_labels() -> void:
	for label in _map.find_children("*", "Label3D", true, false):
		label.visible = false
	for marker in _map.find_children("Marker", "MeshInstance3D", true, false):
		marker.visible = false


func _build_cells() -> void:
	var camera_nodes: Dictionary = _map.get_camera_nodes()
	var ids: Array = camera_nodes.keys()
	ids.sort()

	for id in ids:
		var anchor_node := camera_nodes[id] as Node3D
		var source_camera := anchor_node.get_node("Camera3D") as Camera3D
		var room_id := String(anchor_node.get_meta("room", ""))
		var index := _cells.size()

		var cell := Control.new()
		cell.name = "Cell_" + String(id)
		cell.custom_minimum_size = Vector2(340, 191)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.gui_input.connect(_on_cell_gui_input.bind(index))
		_monitor_grid.add_child(cell)

		var container := SubViewportContainer.new()
		container.name = "View"
		container.stretch = true
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.set_anchors_preset(Control.PRESET_FULL_RECT)
		cell.add_child(container)

		var viewport := SubViewport.new()
		viewport.name = "SubViewport"
		viewport.size = VIEWPORT_SIZE
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(viewport)

		var camera := Camera3D.new()
		camera.name = "Camera3D"
		camera.fov = source_camera.fov
		camera.current = true
		viewport.add_child(camera)
		camera.global_transform = source_camera.global_transform

		var caption := Label.new()
		caption.name = "Caption"
		caption.text = "%s · %s" % [String(id), _map.get_room_display_name(room_id)]
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.add_theme_font_size_override("font_size", 14)
		caption.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 0.95))
		caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		caption.add_theme_constant_override("outline_size", 4)
		caption.anchor_top = 1.0
		caption.anchor_bottom = 1.0
		caption.offset_left = 8.0
		caption.offset_top = -26.0
		caption.offset_right = 260.0
		caption.offset_bottom = -6.0
		cell.add_child(caption)

		_cells.append({
			"id": String(id),
			"room": room_id,
			"source": source_camera,
			"camera": camera,
			"viewport": viewport,
			"cell": cell,
		})


func _setup_zoom_view() -> void:
	_zoom_viewport.size = get_viewport().size
	_zoom_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_zoom_camera.current = true
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

func _enter_focus(index: int) -> void:
	_kill_tween()
	active_cell_index = index
	var source: Camera3D = _cells[index].source
	_source_transform = source.global_transform
	_source_fov = source.fov

	var forward := -_source_transform.basis.z
	_focus_start_transform = Transform3D(_source_transform.basis, _source_transform.origin - forward * transition_pull_back)
	_focus_start_fov = source.fov * transition_fov_widen

	state = FocusState.TRANSITION_IN
	focus_changed.emit(state)

	_zoom_camera.global_transform = _focus_start_transform
	_zoom_camera.fov = _focus_start_fov
	_transition_layer.visible = true
	_transition_layer.modulate.a = 0.0
	_scanline.visible = false
	_back_hint.visible = false

	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_zoom_camera, "global_transform", _source_transform, transition_duration)
	_tween.tween_property(_zoom_camera, "fov", _source_fov, transition_duration)
	_tween.tween_property(_monitor_grid, "modulate:a", 0.0, transition_duration)
	_tween.tween_property(_transition_layer, "modulate:a", 1.0, transition_duration)
	_tween.finished.connect(_on_enter_finished, CONNECT_ONE_SHOT)


func _on_enter_finished() -> void:
	if state != FocusState.TRANSITION_IN:
		return
	_set_focused_visuals()
	state = FocusState.FOCUSED
	focus_changed.emit(state)


func _leave_focus() -> void:
	_kill_tween()
	state = FocusState.TRANSITION_OUT
	focus_changed.emit(state)
	_scanline.visible = false
	_back_hint.visible = false

	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_zoom_camera, "global_transform", _focus_start_transform, transition_duration)
	_tween.tween_property(_zoom_camera, "fov", _focus_start_fov, transition_duration)
	_tween.tween_property(_monitor_grid, "modulate:a", 1.0, transition_duration)
	_tween.tween_property(_transition_layer, "modulate:a", 0.0, transition_duration)
	_tween.finished.connect(_on_leave_finished, CONNECT_ONE_SHOT)


func _on_leave_finished() -> void:
	if state != FocusState.TRANSITION_OUT:
		return
	_set_grid_visuals()
	state = FocusState.GRID
	focus_changed.emit(state)


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
		(cell.cell as Control).mouse_filter = filter


## 杀掉进行中的 Tween；若中途终止则按过渡方向收敛，保证 visible/modulate/state 一致。
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
