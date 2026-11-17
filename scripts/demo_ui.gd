extends RefCounted
## demo 场景用的小 UI 构建工具（纯静态方法，不持有状态）。

const COLOR_TEXT := Color(0.84, 0.88, 0.94)
const COLOR_TITLE := Color(0.93, 0.96, 1.0)
const COLOR_MUTED := Color(0.6, 0.66, 0.76)
const COLOR_OK := Color(0.55, 0.92, 0.72)
const COLOR_WARN := Color(0.98, 0.78, 0.42)
const COLOR_BAD := Color(0.98, 0.55, 0.55)

static func label(text: String, font_size: int = 16, color: Color = COLOR_TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return node


static func button(text: String) -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	return node


static func vbox(separation: int = 8) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func hbox(separation: int = 12) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func panel(bg: Color = Color(0.09, 0.10, 0.13, 0.94)) -> PanelContainer:
	var node := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	node.add_theme_stylebox_override("panel", style)
	return node


static func progress_bar() -> ProgressBar:
	var node := ProgressBar.new()
	node.max_value = 100.0
	node.value = 0.0
	node.custom_minimum_size = Vector2(0, 14)
	node.show_percentage = false
	return node


static func divider() -> HSeparator:
	var node := HSeparator.new()
	node.custom_minimum_size = Vector2(0, 2)
	return node
