extends Control
## demo：录像带数据模型 —— 实时场景「发现」磁带 → 档案库只显示已发现的 → 播放定位。
##
## 数据来源：TapeArchive（autoload）持有的 TapeResource(.tres)。
## 播放定位：TimeManager.archive_time（只读），带内事件由 TapeResource.event_timeline 驱动。

const DemoUI = preload("res://scripts/demo_ui.gd")

var _shelf_list: VBoxContainer
var _archive_list: VBoxContainer
var _detail_label: Label
var _play_button: Button
var _stop_button: Button
var _progress: ProgressBar
var _progress_label: Label
var _event_log: VBoxContainer
var _status_label: Label
var _selected_tape = null


func _ready() -> void:
	TapeArchive.load_default_library()
	_build_ui()
	TapeArchive.tapes_changed.connect(_on_tapes_changed)
	TimeManager.archive_time_changed.connect(_on_archive_time_changed)
	TimeManager.tape_event_triggered.connect(_on_tape_event)
	TimeManager.archive_finished.connect(_on_archive_finished)
	_refresh_all()


# --- 对外查询（供工具验证） ---------------------------------------------------

func get_demo_state() -> Dictionary:
	var selected := ""
	if _selected_tape != null:
		selected = String(_selected_tape.tape_id)
	return {
		"tapes_total": TapeArchive.get_tapes().size(),
		"known_total": TapeArchive.known_count(),
		"known_ids": TapeArchive.get_known_tapes().map(func(t): return String(t.tape_id)),
		"archive_rows": _archive_list.get_child_count(),
		"selected": selected,
		"archive_active": TimeManager.is_archive_active(),
		"archive_time": TimeManager.archive_time,
	}


# --- UI 构建 -----------------------------------------------------------------

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.04, 0.05, 0.07)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)

	var root := DemoUI.vbox(12)
	margin.add_child(root)

	root.add_child(DemoUI.label("录像带数据模型 · 归档与发现", 26, DemoUI.COLOR_TITLE))
	root.add_child(DemoUI.label(
		"左：实时场景的物证架（发现后才进档案库）    右：档案库（只显示 known_to_player == true）",
		14, DemoUI.COLOR_MUTED))

	var columns := DemoUI.hbox(16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	# 左：物证架
	var shelf_panel := DemoUI.panel()
	shelf_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf_panel.size_flags_stretch_ratio = 0.42
	columns.add_child(shelf_panel)
	var shelf_box := DemoUI.vbox(10)
	shelf_panel.add_child(shelf_box)
	shelf_box.add_child(DemoUI.label("物证架 · 实时场景", 18, DemoUI.COLOR_TITLE))
	shelf_box.add_child(DemoUI.label("架子上的带子标签可能是模糊的；点一下才算「发现」。", 13, DemoUI.COLOR_MUTED))
	_shelf_list = DemoUI.vbox(8)
	shelf_box.add_child(_shelf_list)
	var reset_button := DemoUI.button("重置发现状态")
	reset_button.name = "ResetDiscovery"
	reset_button.pressed.connect(_on_reset_pressed)
	shelf_box.add_child(reset_button)

	# 右：档案库 + 播放
	var archive_panel := DemoUI.panel()
	archive_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	archive_panel.size_flags_stretch_ratio = 0.58
	columns.add_child(archive_panel)
	var archive_box := DemoUI.vbox(10)
	archive_panel.add_child(archive_box)
	archive_box.add_child(DemoUI.label("档案库 · 仅显示已发现", 18, DemoUI.COLOR_TITLE))
	_archive_list = DemoUI.vbox(6)
	archive_box.add_child(_archive_list)

	archive_box.add_child(DemoUI.divider())
	_detail_label = DemoUI.label("未选择磁带", 14, DemoUI.COLOR_MUTED)
	archive_box.add_child(_detail_label)

	var buttons := DemoUI.hbox(10)
	archive_box.add_child(buttons)
	_play_button = DemoUI.button("进入档案播放")
	_play_button.name = "PlayButton"
	_play_button.disabled = true
	_play_button.pressed.connect(_on_play_pressed)
	buttons.add_child(_play_button)
	_stop_button = DemoUI.button("停止 / 回到实时")
	_stop_button.name = "StopButton"
	_stop_button.pressed.connect(_on_stop_pressed)
	buttons.add_child(_stop_button)

	_progress = DemoUI.progress_bar()
	archive_box.add_child(_progress)
	_progress_label = DemoUI.label("—", 13, DemoUI.COLOR_MUTED)
	archive_box.add_child(_progress_label)

	archive_box.add_child(DemoUI.label("带内事件", 15, DemoUI.COLOR_TITLE))
	_event_log = DemoUI.vbox(4)
	archive_box.add_child(_event_log)

	_status_label = DemoUI.label("", 13, DemoUI.COLOR_MUTED)
	root.add_child(_status_label)


# --- 刷新 --------------------------------------------------------------------

func _refresh_all() -> void:
	_refresh_shelf()
	_refresh_archive()
	_refresh_playback()


func _refresh_shelf() -> void:
	_clear_children(_shelf_list)
	for tape in TapeArchive.get_tapes():
		var row := DemoUI.hbox(10)
		row.add_child(DemoUI.label("%s ｜ 标签「%s」" % [String(tape.tape_id), String(tape.label)], 15))
		if tape.known_to_player:
			row.add_child(DemoUI.label("已收录", 14, DemoUI.COLOR_OK))
		else:
			var discover := DemoUI.button("发现并收录")
			discover.name = "Discover_" + String(tape.tape_id)
			discover.pressed.connect(_on_discover_pressed.bind(String(tape.tape_id)))
			row.add_child(discover)
		_shelf_list.add_child(row)


func _refresh_archive() -> void:
	_clear_children(_archive_list)
	var known := TapeArchive.get_known_tapes()
	if known.is_empty():
		_archive_list.add_child(DemoUI.label("（空：还没有发现任何磁带）", 14, DemoUI.COLOR_MUTED))
		_selected_tape = null
		return
	for tape in known:
		var row := DemoUI.button("▶ " + String(tape.summary_text()))
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.name = "Archive_" + String(tape.tape_id)
		row.pressed.connect(_on_tape_selected.bind(tape))
		_archive_list.add_child(row)
	if _selected_tape == null or not _selected_tape.known_to_player:
		_selected_tape = known[0]
	_refresh_detail()


func _refresh_detail() -> void:
	if _selected_tape == null:
		_detail_label.text = "未选择磁带"
		_play_button.disabled = true
		return
	_detail_label.text = "选中：%s ｜ 区间 %s–%s ｜ 片长 %s ｜ %d 个带内事件" % [
		String(_selected_tape.display_name()),
		_fmt(_selected_tape.time_start),
		_fmt(_selected_tape.time_end),
		_fmt(_selected_tape.duration()),
		_selected_tape.event_timeline.size(),
	]
	_play_button.disabled = false


func _refresh_playback() -> void:
	if _selected_tape == null or not TimeManager.is_archive_active():
		_progress.value = 0.0
		_progress_label.text = "—"
		_status_label.text = "当前：实时（未在播放档案）"
		return
	var length: float = maxf(0.01, _selected_tape.duration())
	var relative: float = clampf(TimeManager.archive_time - _selected_tape.time_start, 0.0, length)
	_progress.value = relative / length * 100.0
	_progress_label.text = "%s / %s（档案时间 %s）" % [
		_fmt(relative),
		_fmt(length),
		_fmt(TimeManager.archive_time),
	]
	_status_label.text = "当前：档案播放中"


# --- 交互 --------------------------------------------------------------------

func _on_discover_pressed(tape_id: String) -> void:
	TapeArchive.discover(tape_id)


func _on_reset_pressed() -> void:
	if TimeManager.is_archive_active():
		TimeManager.exit_archive()
	TapeArchive.reset_discovery()
	_selected_tape = null
	_clear_children(_event_log)
	_refresh_all()


func _on_tape_selected(tape) -> void:
	_selected_tape = tape
	_refresh_detail()
	_refresh_playback()


func _on_play_pressed() -> void:
	if _selected_tape == null:
		return
	if TimeManager.is_archive_active():
		TimeManager.exit_archive()
	_clear_children(_event_log)
	TimeManager.enter_archive(_selected_tape)
	_progress_label.text = "开始播放 %s" % String(_selected_tape.tape_id)
	_refresh_playback()


func _on_stop_pressed() -> void:
	if TimeManager.is_archive_active():
		TimeManager.exit_archive()
	_refresh_playback()


func _on_tapes_changed() -> void:
	_refresh_shelf()
	_refresh_archive()
	_refresh_playback()


func _on_archive_time_changed(_archive_time: float) -> void:
	_refresh_playback()


func _on_tape_event(event_id: String, at_time: float) -> void:
	_event_log.add_child(DemoUI.label(
		"@%s  %s" % [_fmt(at_time), event_id], 13, DemoUI.COLOR_WARN))


func _on_archive_finished(_tape) -> void:
	_event_log.add_child(DemoUI.label("— 播放结束 —", 13, DemoUI.COLOR_MUTED))


# --- 工具 --------------------------------------------------------------------

func _fmt(seconds: float) -> String:
	var total := maxi(0, int(round(seconds)))
	return "%02d:%02d" % [total / 60, total % 60]


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
