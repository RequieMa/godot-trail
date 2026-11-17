extends Control
## demo：TimeManager —— 双时钟 + 救援事件时间轴 + 档案模式下的静默记录与补播。
##
## present_time 实时推进；archive_time 只读，仅用于档案播放定位。
## 救援事件由时间轴数组驱动，不散落在 _process 条件里。
## 档案模式下 present_time 照常走，但事件只记入 deferred_events，
## 回到实时时一次性补播（模拟「你不在时监控录下的画面」）。

const DemoUI = preload("res://scripts/demo_ui.gd")

var _present_label: Label
var _archive_label: Label
var _mode_label: Label
var _event_list: VBoxContainer
var _log_box: VBoxContainer
var _queue_label: Label
var _event_rows: Array = []


func _ready() -> void:
	_build_ui()
	TimeManager.present_time_changed.connect(_on_present_time_changed)
	TimeManager.archive_time_changed.connect(_on_archive_time_changed)
	TimeManager.rescue_event_triggered.connect(_on_rescue_event)
	TimeManager.rescue_event_deferred.connect(_on_rescue_deferred)
	TimeManager.deferred_events_flushed.connect(_on_deferred_flushed)
	TimeManager.archive_mode_changed.connect(_on_archive_mode_changed)
	TimeManager.rescue_events = TimeManager.rescue_events.duplicate(true)
	_refresh_clocks()
	_rebuild_event_rows()
	_refresh_mode()


# --- 对外查询（供工具验证） ---------------------------------------------------

func get_demo_state() -> Dictionary:
	return {
		"present_time": TimeManager.present_time,
		"archive_time": TimeManager.archive_time,
		"mode": "ARCHIVE" if TimeManager.mode == TimeManager.Mode.ARCHIVE else "REALTIME",
		"fired": TimeManager.fired_events.size(),
		"deferred": TimeManager.deferred_events.size(),
		"pending": TimeManager.pending_events(),
		"speed": TimeManager.speed,
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
	root.add_child(DemoUI.label("TimeManager · 双时钟与救援时间轴", 26, DemoUI.COLOR_TITLE))
	root.add_child(DemoUI.label(
		"present_time 持续前进；档案模式期间事件只静默记录，回到实时时补播",
		14, DemoUI.COLOR_MUTED))

	var columns := DemoUI.hbox(16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	# 左：时钟
	var clock_panel := DemoUI.panel()
	clock_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_panel.size_flags_stretch_ratio = 0.45
	columns.add_child(clock_panel)
	var clock_box := DemoUI.vbox(10)
	clock_panel.add_child(clock_box)
	clock_box.add_child(DemoUI.label("时钟", 18, DemoUI.COLOR_TITLE))
	_present_label = DemoUI.label("00:00", 40, DemoUI.COLOR_TITLE)
	clock_box.add_child(_present_label)
	clock_box.add_child(DemoUI.label("present_time（实时，驱动救援事件）", 13, DemoUI.COLOR_MUTED))
	clock_box.add_child(DemoUI.divider())
	_archive_label = DemoUI.label("archive_time 00:00", 18, DemoUI.COLOR_TEXT)
	clock_box.add_child(_archive_label)
	clock_box.add_child(DemoUI.label("archive_time（只读，仅供录像定位）", 13, DemoUI.COLOR_MUTED))
	_mode_label = DemoUI.label("", 16, DemoUI.COLOR_OK)
	clock_box.add_child(_mode_label)
	_queue_label = DemoUI.label("", 13, DemoUI.COLOR_MUTED)
	clock_box.add_child(_queue_label)

	clock_box.add_child(DemoUI.divider())
	clock_box.add_child(DemoUI.label("时间流速", 14, DemoUI.COLOR_MUTED))
	var speed_row := DemoUI.hbox(8)
	clock_box.add_child(speed_row)
	for speed in [1.0, 5.0, 20.0]:
		var speed_button := DemoUI.button("x%d" % int(speed))
		speed_button.name = "Speed_%d" % int(speed)
		speed_button.pressed.connect(_on_speed_pressed.bind(speed))
		speed_row.add_child(speed_button)

	var mode_row := DemoUI.hbox(8)
	clock_box.add_child(mode_row)
	var enter_button := DemoUI.button("进入档案室")
	enter_button.name = "EnterArchive"
	enter_button.pressed.connect(_on_enter_archive)
	mode_row.add_child(enter_button)
	var exit_button := DemoUI.button("回到实时")
	exit_button.name = "ExitArchive"
	exit_button.pressed.connect(_on_exit_archive)
	mode_row.add_child(exit_button)
	var reset_button := DemoUI.button("重置时间轴")
	reset_button.name = "ResetTimeline"
	reset_button.pressed.connect(_on_reset)
	clock_box.add_child(reset_button)

	# 右：事件时间轴 + 日志
	var event_panel := DemoUI.panel()
	event_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_panel.size_flags_stretch_ratio = 0.55
	columns.add_child(event_panel)
	var event_box := DemoUI.vbox(10)
	event_panel.add_child(event_box)
	event_box.add_child(DemoUI.label("救援事件时间轴", 18, DemoUI.COLOR_TITLE))
	_event_list = DemoUI.vbox(6)
	event_box.add_child(_event_list)
	event_box.add_child(DemoUI.divider())
	event_box.add_child(DemoUI.label("触发日志", 15, DemoUI.COLOR_TITLE))
	_log_box = DemoUI.vbox(3)
	event_box.add_child(_log_box)


# --- 刷新 --------------------------------------------------------------------

func _refresh_clocks() -> void:
	_present_label.text = TimeManager.format_clock(TimeManager.present_time)
	_archive_label.text = "archive_time " + TimeManager.format_clock(TimeManager.archive_time)
	_queue_label.text = "已触发 %d ｜ 待触发 %d ｜ 静默记录 %d" % [
		TimeManager.fired_events.size(),
		TimeManager.pending_events(),
		TimeManager.deferred_events.size(),
	]


func _refresh_mode() -> void:
	if TimeManager.mode == TimeManager.Mode.ARCHIVE:
		_mode_label.text = "模式：档案（事件静默记录中）"
		_mode_label.add_theme_color_override("font_color", DemoUI.COLOR_WARN)
	else:
		_mode_label.text = "模式：实时（事件即时触发）"
		_mode_label.add_theme_color_override("font_color", DemoUI.COLOR_OK)


func _rebuild_event_rows() -> void:
	for child in _event_list.get_children():
		_event_list.remove_child(child)
		child.queue_free()
	_event_rows.clear()

	for entry in TimeManager.rescue_events:
		var row := DemoUI.hbox(12)
		var at := float(entry.get("t", 0.0))
		row.add_child(DemoUI.label("t=%s" % TimeManager.format_clock(at), 15, DemoUI.COLOR_MUTED))
		row.add_child(DemoUI.label(String(entry.get("event", "")), 15))
		var status := DemoUI.label(_status_for(String(entry.get("event", ""))), 14, DemoUI.COLOR_MUTED)
		row.add_child(status)
		_event_list.add_child(row)

	refresh_event_status()


func _status_for(event_id: String) -> String:
	for record in TimeManager.fired_events:
		if String(record.get("id", "")) == event_id:
			return "已补播" if bool(record.get("deferred", false)) else "已触发"
	for record in TimeManager.deferred_events:
		if String(record.get("id", "")) == event_id:
			return "档案期间记录"
	return "待触发"


func refresh_event_status() -> void:
	var index := 0
	for entry in TimeManager.rescue_events:
		var row := _event_list.get_child(index) as HBoxContainer
		index += 1
		if row == null or row.get_child_count() < 3:
			continue
		var status := row.get_child(2) as Label
		var text := _status_for(String(entry.get("event", "")))
		status.text = text
		var color := DemoUI.COLOR_MUTED
		if text == "已触发":
			color = DemoUI.COLOR_OK
		elif text == "已补播":
			color = DemoUI.COLOR_WARN
		elif text == "档案期间记录":
			color = DemoUI.COLOR_BAD
		status.add_theme_color_override("font_color", color)


func _append_log(text: String, color: Color) -> void:
	_log_box.add_child(DemoUI.label(text, 13, color))
	while _log_box.get_child_count() > 12:
		var first := _log_box.get_child(0)
		_log_box.remove_child(first)
		first.queue_free()


# --- 信号 --------------------------------------------------------------------

func _on_present_time_changed(_value: float) -> void:
	_refresh_clocks()


func _on_archive_time_changed(_value: float) -> void:
	_refresh_clocks()


func _on_rescue_event(event_id: String, at_time: float, deferred: bool) -> void:
	var prefix := "补播" if deferred else "触发"
	_append_log("[%s] %s @ %s" % [prefix, event_id, TimeManager.format_clock(at_time)],
		DemoUI.COLOR_WARN if deferred else DemoUI.COLOR_OK)
	refresh_event_status()
	_refresh_clocks()


func _on_rescue_deferred(event_id: String, at_time: float) -> void:
	_append_log("[静默记录] %s @ %s" % [event_id, TimeManager.format_clock(at_time)], DemoUI.COLOR_BAD)
	refresh_event_status()
	_refresh_clocks()


func _on_deferred_flushed(events: Array) -> void:
	_append_log("— 回到实时，补播 %d 条监控记录 —" % events.size(), DemoUI.COLOR_WARN)


func _on_archive_mode_changed(_active: bool) -> void:
	_refresh_mode()
	refresh_event_status()


# --- 交互 --------------------------------------------------------------------

func _on_speed_pressed(speed: float) -> void:
	TimeManager.speed = speed
	_refresh_clocks()


func _on_enter_archive() -> void:
	TimeManager.enter_archive(null)
	_append_log("进入档案室：之后的救援事件只静默记录", DemoUI.COLOR_MUTED)


func _on_exit_archive() -> void:
	TimeManager.exit_archive()
	_append_log("回到实时：补播错过的监控记录", DemoUI.COLOR_MUTED)


func _on_reset() -> void:
	TimeManager.reset()
	for child in _log_box.get_children():
		_log_box.remove_child(child)
		child.queue_free()
	_rebuild_event_rows()
	_refresh_clocks()
	_refresh_mode()
