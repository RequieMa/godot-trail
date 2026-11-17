extends Node
## 录像带档案库（autoload）。
##
## 负责持有磁带资源、维护「玩家是否已发现」，并提供档案库/实时场景两侧的查询接口。
## 档案库界面只显示 known_to_player == true 的磁带。

signal tapes_changed()
signal tape_discovered(tape_id: String)

## 默认磁带库（.tres 资源，便于后续替换/扩展）
const DEFAULT_LIBRARY: Array[String] = [
	"res://resources/tapes/tape_a317.tres",
	"res://resources/tapes/tape_unknown_1.tres",
	"res://resources/tapes/tape_unknown_2.tres",
]

var _tapes: Array = []
var _by_id: Dictionary = {}


## 载入默认磁带库（重复调用安全）。
func load_default_library() -> void:
	if not _tapes.is_empty():
		return
	for path in DEFAULT_LIBRARY:
		var tape = load(path)
		if tape == null:
			push_error("无法加载录像带资源: %s" % path)
			continue
		register_tape(tape)


func register_tape(tape) -> void:
	if tape == null:
		return
	var tape_id: String = String(tape.tape_id)
	if tape_id.is_empty() or _by_id.has(tape_id):
		return
	_tapes.append(tape)
	_by_id[tape_id] = tape
	tapes_changed.emit()


func get_tapes() -> Array:
	return _tapes.duplicate()


func get_known_tapes() -> Array:
	var result: Array = []
	for tape in _tapes:
		if tape.known_to_player:
			result.append(tape)
	return result


func get_tape(tape_id: String):
	return _by_id.get(tape_id)


## 玩家在实时场景里发现某盘带：置 known_to_player 并广播。
## 已发现过则返回 false。
func discover(tape_id: String) -> bool:
	var tape = _by_id.get(tape_id)
	if tape == null or tape.known_to_player:
		return false
	tape.known_to_player = true
	tape_discovered.emit(tape_id)
	tapes_changed.emit()
	return true


func known_count() -> int:
	return get_known_tapes().size()


## 仅供 demo 重置用。
func reset_discovery() -> void:
	for tape in _tapes:
		tape.known_to_player = false
	tapes_changed.emit()
