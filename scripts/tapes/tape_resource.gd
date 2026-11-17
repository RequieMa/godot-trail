class_name TapeResource
extends Resource
## 一盘录像带的数据模型。
##
## 标签（label）可能是模糊的或错误的——玩家在档案库里看到的未必是真编号，
## 真编号由 tape_id 承载，供程序逻辑使用。
## 事件时间轴 event_timeline 用相对带首的秒数（t），而不是绝对时间，
## 这样同一盘带在档案库与实时时间线上都能复用。

## 磁带编号（程序用，唯一）
@export var tape_id: String = ""
## 标签（玩家可见，可能模糊/错误）
@export var label: String = ""
## 带内起始时间（绝对时间轴上的秒数）
@export var time_start: float = 0.0
## 带内结束时间（绝对时间轴上的秒数）
@export var time_end: float = 0.0
## 视频源（占位阶段可为空，仅用事件时间轴驱动）
@export var stream: VideoStream = null
## 带内事件时间轴：[{ "t": 相对带首秒数, "event": 事件名/描述 }]
@export var event_timeline: Array[Dictionary] = []
## 玩家是否已找到这盘带（档案库只显示 true 的）
@export var known_to_player: bool = false


## 片长（秒）：有视频源用视频长度，否则用起止时间差。
func duration() -> float:
	if stream != null and stream.get_length() > 0.0:
		return stream.get_length()
	return maxf(0.0, time_end - time_start)


## 该绝对时间是否落在这盘带的区间内。
func contains_time(absolute_time: float) -> bool:
	return absolute_time >= time_start and absolute_time <= time_end


## 播放位置（带内相对秒）换算成绝对时间。
func to_absolute_time(relative_time: float) -> float:
	return time_start + relative_time


## 取出 (from, to] 区间内的事件（参数为带内相对秒）。
func events_between(from_time: float, to_time: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in event_timeline:
		var at := float(entry.get("t", 0.0))
		if at > from_time and at <= to_time:
			result.append(entry)
	return result


## 播放用的显示名：编号 + 标签。
func display_name() -> String:
	var clean_label := label if not label.is_empty() else "（无标签）"
	return "%s · %s" % [tape_id, clean_label]


## 档案库列表里的一行文字。
func summary_text() -> String:
	return "%s ｜ %s ｜ %s" % [tape_id, label, format_seconds(duration())]


static func format_seconds(seconds: float) -> String:
	var total := maxi(0, int(round(seconds)))
	return "%02d:%02d" % [total / 60, total % 60]
