extends Node
## 线索管理器（autoload）：线索是全局标志，不做「消耗/使用」流程。
##
## 线索的「元数据」（标题/来源/解锁目标/交互文案）来自 JSON 定义表
## `resources/data/clues.json`，代码里不再硬编码 clue_id 与取值；
## 运行时的「玩家是否已登记」仍然只在本节点的内存 Dictionary 里。

signal clue_registered(clue_id: String, value: Variant)
signal clues_changed()
signal definitions_loaded(count: int)
signal definition_error(message: String)

const DEFAULT_DEFINITIONS_PATH := "res://resources/data/clues.json"

var _clues: Dictionary = {}
var _definitions: Dictionary = {}
var _definition_order: Array[String] = []


func _ready() -> void:
	load_definitions()


# --- 定义表（JSON） ----------------------------------------------------------

## 载入线索定义表。成功返回 true，失败发 definition_error。
func load_definitions(path: String = DEFAULT_DEFINITIONS_PATH) -> bool:
	_definitions.clear()
	_definition_order.clear()

	var parsed: Variant = _read_json(path)
	if parsed == null:
		definition_error.emit("线索定义读取或解析失败: %s" % path)
		return false
	if not parsed is Dictionary:
		definition_error.emit("线索定义根节点必须是对象: %s" % path)
		return false

	var entries: Variant = (parsed as Dictionary).get("clues", [])
	if not entries is Array:
		definition_error.emit("线索定义的 clues 字段必须是数组: %s" % path)
		return false

	for entry in entries:
		if not entry is Dictionary:
			definition_error.emit("跳过非对象的线索定义: %s" % str(entry))
			continue
		var clue_id := String((entry as Dictionary).get("id", ""))
		if clue_id.is_empty():
			definition_error.emit("线索定义缺少 id，已跳过: %s" % str(entry))
			continue
		_definitions[clue_id] = (entry as Dictionary).duplicate(true)
		_definition_order.append(clue_id)

	definitions_loaded.emit(_definitions.size())
	return true


func _read_json(path: String) -> Variant:
	# 开发/运行期直接读文件；导出后若裸文件不可用，退回 JSON 资源。
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path)
		if not text.is_empty():
			return JSON.parse_string(text)
	if ResourceLoader.exists(path):
		var resource = load(path)
		if resource is JSON:
			return (resource as JSON).data
	return null


func get_definitions() -> Array:
	var result: Array = []
	for clue_id in _definition_order:
		result.append(_definitions[clue_id])
	return result


func get_definition(clue_id: String) -> Dictionary:
	return (_definitions.get(clue_id, {}) as Dictionary).duplicate(true)


func get_definitions_for_unlock(unlock_id: String) -> Array:
	var result: Array = []
	for clue_id in _definition_order:
		var definition: Dictionary = _definitions[clue_id]
		if String(definition.get("unlocks", "")) == unlock_id:
			result.append(definition.duplicate(true))
	return result


## 按定义表取线索的取值（没有定义时返回 true）。
func get_defined_value(clue_id: String) -> Variant:
	var definition: Dictionary = _definitions.get(clue_id, {})
	return definition.get("value", true)


# --- 已登记的线索（运行时状态） ----------------------------------------------

## 登记线索：register_clue("door_code_A") 会从 JSON 取默认值；
## 也允许显式覆盖：register_clue("door_code_A", "A-317")。
func register_clue(clue_id: String, value: Variant = null) -> void:
	var resolved: Variant = value
	if resolved == null:
		resolved = get_defined_value(clue_id)
	_clues[clue_id] = resolved
	clue_registered.emit(clue_id, resolved)
	clues_changed.emit()


func has_clue(clue_id: String) -> bool:
	return _clues.has(clue_id)


func get_clue(clue_id: String, fallback: Variant = null) -> Variant:
	return _clues.get(clue_id, fallback)


func get_all() -> Dictionary:
	return _clues.duplicate(true)


func count() -> int:
	return _clues.size()


func clear() -> void:
	if _clues.is_empty():
		return
	_clues.clear()
	clues_changed.emit()


## 展示用文字：有定义时用「标题 = 值」，否则回落到 id。
func describe(clue_id: String) -> String:
	var definition: Dictionary = _definitions.get(clue_id, {})
	var title := String(definition.get("title", clue_id))
	return "%s = %s" % [title, str(get_clue(clue_id, "?"))]


## 交互文案：从定义表的 action 模板取，{value} 会被替换。
func build_action_text(clue_id: String) -> String:
	var definition: Dictionary = _definitions.get(clue_id, {})
	var template := String(definition.get("action", ""))
	if template.is_empty():
		return ""
	return template.replace("{value}", str(get_clue(clue_id, get_defined_value(clue_id))))
