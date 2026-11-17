extends Node2D
## Game Studio 基线入口脚本（占位，非玩法内容）。
## 仅用于验证项目可导入、可实例化、可运行。

const READY_MARKER := "GODOT_TRAIL_READY"


func _ready() -> void:
	print(READY_MARKER)
