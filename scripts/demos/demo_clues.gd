extends Control
## demo：ClueManager —— 线索定义来自 JSON，交互节点「初始化时」检查是否显示某个选项。
##
## 数据源：resources/data/clues.json（clue 的 id / 取值 / 来源 / 解锁目标 / 交互文案）
## 运行时：只有「玩家是否已登记」在 ClueManager 内存里。
## 门的选项在初始化时读一次 ClueManager.has_clue()，登记新线索后需要重新初始化才生效。

const DemoUI = preload("res://scripts/demo_ui.gd")

## 门的身份（demo 自身的常量，不是线索数据；对应 clues.json 里的 unlocks 字段）
const DOOR_ID := "door_archive"

var _note_list: VBoxContainer
var _clue_list: VBoxContainer
var _door_options: VBoxContainer
var _door_state_label: Label
var _hint_label: Label
var _data_label: Label
var _door_unlocked := false
var _door_initialized_clues: Array = []


func _ready() -> void:
	_build_ui()
	ClueManager.clues_changed.connect(_on_clues_changed)
	ClueManager.definitions_loaded.connect(_on_definitions_loaded)
	ClueManager.definition_error.connect(_on_definition_error)
	_initialize_door()
	_refresh_notes()
	_refresh_clue_list()
	_refresh_hint()


# --- 对外查询（供工具验证） ---------------------------------------------------

func get_demo_state() -> Dictionary:
	var option_names: Array = []
	for child in _door_options.get_children():
		if child is Button:
			option_names.append(String((child as Button).text))
		elif child is Label:
			option_names.append("[label] " + String((child as Label).text))
	return {
		"definitions": ClueManager.get_definitions().size(),
		"definition_ids": ClueManager.get_definitions().map(func(d): return String(d.id)),
		"clues": ClueManager.get_all(),
		"door_option_names": option_names,
		"door_initialized_clues": _door_initialized_clues.duplicate(),
		"door_unlocked": _door_unlocked,
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
	root.add_child(DemoUI.label("ClueManager · JSON 驱动的线索与交互选项", 26, DemoUI.COLOR_TITLE))
	root.add_child(DemoUI.label(
		"线索的 id / 取值 / 来源 / 解锁目标 / 交互文案都来自 clues.json；代码里没有硬编码",
		14, DemoUI.COLOR_MUTED))

	var columns := DemoUI.hbox(16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	# 左：房间（线索来源 + 门）
	var room_panel := DemoUI.panel()
	room_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_panel.size_flags_stretch_ratio = 0.54
	columns.add_child(room_panel)
	var room_box := DemoUI.vbox(10)
	room_panel.add_child(room_box)
	room_box.add_child(DemoUI.label("档案室 · 实时场景", 18, DemoUI.COLOR_TITLE))

	_data_label = DemoUI.label("", 13, DemoUI.COLOR_MUTED)
	room_box.add_child(_data_label)
	_note_list = DemoUI.vbox(6)
	room_box.add_child(_note_list)

	room_box.add_child(DemoUI.divider())
	room_box.add_child(DemoUI.label("门", 16, DemoUI.COLOR_TITLE))
	_door_state_label = DemoUI.label("", 13, DemoUI.COLOR_MUTED)
	room_box.add_child(_door_state_label)
	_door_options = DemoUI.vbox(6)
	room_box.add_child(_door_options)

	var door_buttons := DemoUI.hbox(10)
	room_box.add_child(door_buttons)
	var reinit_button := DemoUI.button("重新初始化门")
	reinit_button.name = "ReinitDoor"
	reinit_button.pressed.connect(_on_reinit_door)
	door_buttons.add_child(reinit_button)
	var reload_button := DemoUI.button("重新加载 clues.json")
	reload_button.name = "ReloadDefinitions"
	reload_button.pressed.connect(_on_reload_definitions)
	door_buttons.add_child(reload_button)
	var clear_button := DemoUI.button("清空线索")
	clear_button.name = "ClearClues"
	clear_button.pressed.connect(_on_clear_clues)
	door_buttons.add_child(clear_button)

	# 右：线索面板
	var clue_panel := DemoUI.panel()
	clue_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clue_panel.size_flags_stretch_ratio = 0.46
	columns.add_child(clue_panel)
	var clue_box := DemoUI.vbox(10)
	clue_panel.add_child(clue_box)
	clue_box.add_child(DemoUI.label("线索面板（已登记，全局标志）", 18, DemoUI.COLOR_TITLE))
	_clue_list = DemoUI.vbox(8)
	clue_box.add_child(_clue_list)
	_hint_label = DemoUI.label("", 13, DemoUI.COLOR_WARN)
	clue_box.add_child(_hint_label)


# --- 线索来源：完全由 JSON 定义生成 -------------------------------------------

func _refresh_notes() -> void:
	_clear(_note_list)
	var definitions := ClueManager.get_definitions()
	_data_label.text = "定义表：%d 条（resources/data/clues.json）" % definitions.size()
	if definitions.is_empty():
		_note_list.add_child(DemoUI.label("（定义表为空，检查 resources/data/clues.json）", 13, DemoUI.COLOR_BAD))
		return
	for definition in definitions:
		var clue_id := String(definition.get("id", ""))
		var source := String(definition.get("source", clue_id))
		var button := DemoUI.button("查看：" + source)
		button.name = "Note_" + clue_id
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_note_pressed.bind(clue_id))
		_note_list.add_child(button)


# --- 门：初始化时决定选项 -----------------------------------------------------

func _initialize_door() -> void:
	_clear(_door_options)
	_door_initialized_clues.clear()

	var unlock_definitions := ClueManager.get_definitions_for_unlock(DOOR_ID)
	for definition in unlock_definitions:
		var clue_id := String(definition.get("id", ""))
		if ClueManager.has_clue(clue_id):
			_door_initialized_clues.append(clue_id)

	_door_state_label.text = "门初始化：JSON 里 %d 条线索指向本门，其中已登记 %d 条" % [
		unlock_definitions.size(), _door_initialized_clues.size()]

	if _door_unlocked:
		_door_options.add_child(DemoUI.label("门已经打开了。", 15, DemoUI.COLOR_OK))
		return

	var pry_button := DemoUI.button("尝试撬门")
	pry_button.name = "DoorOption_Pry"
	pry_button.pressed.connect(_on_pry)
	_door_options.add_child(pry_button)

	for clue_id in _door_initialized_clues:
		var action_text := ClueManager.build_action_text(clue_id)
		if action_text.is_empty():
			continue
		var action_button := DemoUI.button(action_text)
		action_button.name = "DoorOption_" + clue_id
		action_button.pressed.connect(_on_use_clue.bind(clue_id))
		_door_options.add_child(action_button)


# --- 刷新 --------------------------------------------------------------------

func _refresh_clue_list() -> void:
	_clear(_clue_list)
	var all := ClueManager.get_all()
	if all.is_empty():
		_clue_list.add_child(DemoUI.label("（还没有登记任何线索）", 14, DemoUI.COLOR_MUTED))
		return
	for clue_id in all:
		var definition := ClueManager.get_definition(String(clue_id))
		var title := String(definition.get("title", String(clue_id)))
		var description := String(definition.get("description", ""))
		var box := DemoUI.vbox(2)
		box.add_child(DemoUI.label("%s = %s" % [title, str(all[clue_id])], 15, DemoUI.COLOR_OK))
		if not description.is_empty():
			box.add_child(DemoUI.label(description, 12, DemoUI.COLOR_MUTED))
		_clue_list.add_child(box)


func _refresh_hint() -> void:
	var registered_but_unused: Array = []
	for definition in ClueManager.get_definitions_for_unlock(DOOR_ID):
		var clue_id := String(definition.get("id", ""))
		if ClueManager.has_clue(clue_id) and not _door_initialized_clues.has(clue_id):
			registered_but_unused.append(clue_id)
	if registered_but_unused.is_empty() or _door_unlocked:
		_hint_label.text = ""
		return
	_hint_label.text = "已登记 %s，但门尚未重新初始化 —— 点击「重新初始化门」查看选项变化。" % str(registered_but_unused)


# --- 交互 --------------------------------------------------------------------

func _on_note_pressed(clue_id: String) -> void:
	ClueManager.register_clue(clue_id)
	_refresh_clue_list()
	_refresh_hint()


func _on_reinit_door() -> void:
	_initialize_door()
	_refresh_hint()


func _on_reload_definitions() -> void:
	ClueManager.load_definitions()
	_refresh_notes()
	_initialize_door()
	_refresh_clue_list()
	_refresh_hint()


func _on_clear_clues() -> void:
	ClueManager.clear()
	_door_unlocked = false
	_initialize_door()
	_refresh_clue_list()
	_refresh_hint()


func _on_pry() -> void:
	_door_state_label.text = "撬门失败：门被反锁了。"
	_door_state_label.add_theme_color_override("font_color", DemoUI.COLOR_BAD)


func _on_use_clue(_clue_id: String) -> void:
	_door_unlocked = true
	_door_state_label.text = "线索生效，门开了。"
	_door_state_label.add_theme_color_override("font_color", DemoUI.COLOR_OK)
	_clear(_door_options)
	_door_options.add_child(DemoUI.label("门已打开。", 15, DemoUI.COLOR_OK))
	_refresh_hint()


func _on_clues_changed() -> void:
	_refresh_clue_list()
	_refresh_hint()


func _on_definitions_loaded(count: int) -> void:
	_data_label.text = "定义表已载入：%d 条（resources/data/clues.json）" % count


func _on_definition_error(message: String) -> void:
	_data_label.text = message
	_data_label.add_theme_color_override("font_color", DemoUI.COLOR_BAD)


# --- 工具 --------------------------------------------------------------------

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
