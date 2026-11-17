extends SceneTree
## 冒烟测试：验证主场景已配置、可加载、可实例化。
## 运行：godot --headless --path . --script tests/smoke_test.gd
## 退出码 0 = 通过，1 = 失败。

const MAIN_SCENE_SETTING := "application/run/main_scene"


func _initialize() -> void:
	var failures: Array[String] = []
	var main_scene: String = str(ProjectSettings.get_setting(MAIN_SCENE_SETTING, ""))

	if main_scene.is_empty():
		failures.append("%s 未设置" % MAIN_SCENE_SETTING)
	elif not ResourceLoader.exists(main_scene):
		failures.append("主场景资源不存在: %s" % main_scene)
	else:
		var packed := ResourceLoader.load(main_scene) as PackedScene
		if packed == null:
			failures.append("主场景无法作为 PackedScene 加载: %s" % main_scene)
		else:
			var instance := packed.instantiate()
			if instance == null:
				failures.append("主场景实例化失败: %s" % main_scene)
			else:
				instance.free()

	if failures.is_empty():
		print("SMOKE_TEST_PASS")
		quit(0)
	else:
		for failure in failures:
			printerr("SMOKE_TEST_FAIL: ", failure)
		quit(1)
