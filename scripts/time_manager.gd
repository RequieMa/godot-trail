extends Node
## 时间管理器（autoload）：维护「档案时间」与「现在时间」两个时钟。
##
## - present_time：实时推进，驱动救援事件（rescue_events 时间轴）。
## - archive_time：只读，仅供录像播放定位；外部只能通过 enter_archive / seek_archive 影响。
##
## 救援事件不散落在 _process 的条件判断里，而是走时间轴数组，
## 由 present_time 越过阈值时统一分发。档案模式下事件不即时响应，
## 而是静默记入 deferred_events，等玩家回到实时界面时一次性以「监控画面记录」补播。

signal present_time_changed(present_time: float)
signal archive_time_changed(archive_time: float)
## deferred = true 表示这是玩家在档案模式期间错过、回来后才补播的事件
signal rescue_event_triggered(event_id: String, at_time: float, deferred: bool)
signal rescue_event_deferred(event_id: String, at_time: float)
signal deferred_events_flushed(events: Array)
signal archive_mode_changed(active: bool)
signal tape_event_triggered(event_id: String, at_time: float)
signal archive_finished(tape)

enum Mode { REALTIME, ARCHIVE }

const DEFAULT_RESCUE_EVENTS: Array[Dictionary] = [
	{"t": 30.0, "event": "door_locked"},
	{"t": 90.0, "event": "guard_checks_room"},
	{"t": 150.0, "event": "critical_window"},
]

## 实时时钟（秒，单调递增）
var present_time: float = 0.0
## 档案播放位置（秒，只读）
var archive_time: float = 0.0
var mode: Mode = Mode.REALTIME
## 救援事件时间轴：[{ "t": 秒, "event": 事件名 }]
var rescue_events: Array[Dictionary] = []
## 已触发过的救援事件（含补播）
var fired_events: Array[Dictionary] = []
## 档案模式下错过、待补播的事件
var deferred_events: Array[Dictionary] = []
## 时间流速（demo 用，1.0 = 真实速度）
var speed: float = 1.0

var _next_index: int = 0
var _archive_tape = null
var _archive_playing := false


func _ready() -> void:
	set_rescue_events(DEFAULT_RESCUE_EVENTS.duplicate(true))


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var scaled := delta * speed
	advance_present_time(scaled)
	if mode == Mode.ARCHIVE and _archive_playing:
		_advance_archive(scaled)


# --- 救援事件时间轴 ----------------------------------------------------------

func set_rescue_events(events: Array) -> void:
	rescue_events.clear()
	for entry in events:
		rescue_events.append((entry as Dictionary).duplicate(true))
	rescue_events.sort_custom(func(a, b): return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	_next_index = 0


func advance_present_time(delta: float) -> void:
	present_time += delta
	present_time_changed.emit(present_time)
	while _next_index < rescue_events.size():
		var entry: Dictionary = rescue_events[_next_index]
		var at := float(entry.get("t", 0.0))
		if at > present_time:
			break
		_next_index += 1
		_dispatch_rescue_event(entry, at)


func _dispatch_rescue_event(entry: Dictionary, at: float) -> void:
	var event_id := String(entry.get("event", ""))
	if mode == Mode.ARCHIVE:
		deferred_events.append({"id": event_id, "at": at, "recorded_at": present_time})
		rescue_event_deferred.emit(event_id, at)
	else:
		fired_events.append({"id": event_id, "at": at, "deferred": false})
		rescue_event_triggered.emit(event_id, at, false)


func pending_events() -> int:
	return maxi(0, rescue_events.size() - _next_index)


# --- 档案模式 ----------------------------------------------------------------

## 进入档案模式。tape 可为空（只作为「离开实时」的开关，archive_time 从 0 走）。
func enter_archive(tape = null) -> void:
	_archive_tape = tape
	_archive_playing = true
	mode = Mode.ARCHIVE
	archive_time = tape.time_start if tape != null else 0.0
	archive_time_changed.emit(archive_time)
	archive_mode_changed.emit(true)


## 回到实时：先切模式，再把档案期间错过的事件补播出去。
func exit_archive() -> void:
	if mode != Mode.ARCHIVE:
		return
	_archive_playing = false
	mode = Mode.REALTIME
	archive_mode_changed.emit(false)
	_flush_deferred_events()


## 定位播放位置（绝对档案时间，会被限制在磁带区间内）。
func seek_archive(absolute_time: float) -> void:
	var target := maxf(0.0, absolute_time)
	if _archive_tape != null:
		target = clampf(target, _archive_tape.time_start, _archive_tape.time_end)
	archive_time = target
	archive_time_changed.emit(archive_time)


func get_archive_tape():
	return _archive_tape


func is_archive_active() -> bool:
	return mode == Mode.ARCHIVE


func _advance_archive(delta: float) -> void:
	if _archive_tape == null:
		archive_time += delta
		archive_time_changed.emit(archive_time)
		return

	var previous := archive_time
	var end_time: float = _archive_tape.time_end
	archive_time = minf(archive_time + delta, end_time)

	var from_relative: float = previous - float(_archive_tape.time_start)
	var to_relative: float = archive_time - float(_archive_tape.time_start)
	for entry in _archive_tape.events_between(from_relative, to_relative):
		tape_event_triggered.emit(String(entry.get("event", "")), float(entry.get("t", 0.0)))

	archive_time_changed.emit(archive_time)
	if archive_time >= end_time:
		_archive_playing = false
		archive_finished.emit(_archive_tape)


func _flush_deferred_events() -> void:
	if deferred_events.is_empty():
		return
	var flushed := deferred_events.duplicate(true)
	deferred_events.clear()
	deferred_events_flushed.emit(flushed)
	for record in flushed:
		fired_events.append({"id": String(record.get("id", "")), "at": float(record.get("at", 0.0)), "deferred": true})
		rescue_event_triggered.emit(String(record.get("id", "")), float(record.get("at", 0.0)), true)


# --- 工具 --------------------------------------------------------------------

func format_clock(seconds: float) -> String:
	var total := maxi(0, int(seconds))
	return "%02d:%02d" % [total / 60, total % 60]


## demo 重置
func reset() -> void:
	present_time = 0.0
	archive_time = 0.0
	mode = Mode.REALTIME
	fired_events.clear()
	deferred_events.clear()
	_archive_tape = null
	_archive_playing = false
	_next_index = 0
	present_time_changed.emit(present_time)
	archive_time_changed.emit(archive_time)
	archive_mode_changed.emit(false)
