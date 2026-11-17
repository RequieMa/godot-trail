extends Node3D
class_name TheaterMap
## 剧院平面占位地图（俯视）。数据驱动：房间 / 通道 / 摄像头写在常量表里，
## 运行时生成地板、墙体、标签、摄像头挂点与占位道具，方便后续替换真实关卡。
##
## 约定：x 轴向右（东），z 轴向下（南），y 轴向上；1 单位 = 1 米。

const WALL_HEIGHT := 2.4
const WALL_THICKNESS := 0.16
const FLOOR_THICKNESS := 0.1
const CAMERA_HEIGHT := 2.1
## 天花板所在的 3D 渲染层（2 = 第 2 层）。俯视相机只渲染第 1 层。
const CEILING_LAYER := 2
const EPSILON := 0.01

## kind: normal / fire（起火点） / blind（盲区：内部无镜头）
const ROOMS: Array[Dictionary] = [
	{"id": "stairs", "name": "楼梯", "note": "通二楼，第一幕锁", "rect": Rect2(0.0, 0.0, 5.6, 4.0), "kind": "normal"},
	{"id": "corridor", "name": "走廊", "note": "绕路，较长", "rect": Rect2(7.0, 0.0, 10.0, 4.0), "kind": "normal"},
	{"id": "prop_room", "name": "道具仓", "note": "盲区：内部无镜头", "rect": Rect2(18.4, 0.0, 8.6, 4.0), "kind": "blind"},
	{"id": "lobby", "name": "大厅", "note": "锚点 A · 开局", "rect": Rect2(0.0, 4.0, 5.6, 10.4), "kind": "normal"},
	{"id": "seating", "name": "观众席", "note": "大熊起点", "rect": Rect2(7.0, 4.0, 10.0, 10.4), "kind": "normal"},
	{"id": "stage", "name": "舞台", "note": "起火点", "rect": Rect2(18.4, 4.0, 3.8, 10.4), "kind": "fire"},
	{"id": "backstage", "name": "后台", "note": "锚点 B", "rect": Rect2(23.6, 4.0, 3.4, 10.4), "kind": "normal"},
	{"id": "front_gate", "name": "正门", "note": "被堵死", "rect": Rect2(0.0, 14.4, 5.6, 3.2), "kind": "normal"},
	{"id": "side_gate", "name": "侧门", "note": "出口 / 敌人入口", "rect": Rect2(20.0, 14.4, 7.0, 3.2), "kind": "normal"},
]

## kind: open（通道） / blocked（堵死）
const LINKS: Array[Dictionary] = [
	{"a": "stairs", "b": "lobby", "kind": "open"},
	{"a": "lobby", "b": "seating", "kind": "open"},
	{"a": "seating", "b": "corridor", "kind": "open"},
	{"a": "corridor", "b": "prop_room", "kind": "open"},
	{"a": "seating", "b": "stage", "kind": "open"},
	{"a": "stage", "b": "backstage", "kind": "open"},
	{"a": "backstage", "b": "side_gate", "kind": "open"},
	{"a": "prop_room", "b": "backstage", "kind": "blocked"},
	{"a": "lobby", "b": "front_gate", "kind": "blocked"},
]

## frac：在该房间矩形内的相对位置（0~1）；look 为朝向的相对目标点（默认房间中心）。
const CAMERAS: Array[Dictionary] = [
	{"id": "C1", "room": "lobby", "frac": Vector2(0.18, 0.14), "look": Vector2(0.5, 0.88)},
	{"id": "C2", "room": "seating", "frac": Vector2(0.86, 0.16), "look": Vector2(0.45, 0.6)},
	{"id": "C3", "room": "stage", "frac": Vector2(0.5, 0.84), "look": Vector2(0.5, 0.3)},
	{"id": "C4", "room": "corridor", "frac": Vector2(0.9, 0.5), "look": Vector2(0.1, 0.5)},
	{"id": "C5", "room": "prop_room", "frac": Vector2(0.03, 0.5), "look": Vector2(0.55, 0.5)},
	{"id": "C6", "room": "backstage", "frac": Vector2(0.5, 0.86), "look": Vector2(0.7, 0.4)},
	{"id": "C7", "room": "side_gate", "frac": Vector2(0.86, 0.5), "look": Vector2(0.15, 0.5)},
	{"id": "C8", "room": "stairs", "frac": Vector2(0.5, 0.84), "look": Vector2(0.5, 0.4)},
	{"id": "C9", "room": "front_gate", "frac": Vector2(0.5, 0.86), "look": Vector2(0.5, 0.2)},
]

var _rooms: Dictionary = {}
var _cameras: Dictionary = {}

var _material_floor_normal: StandardMaterial3D
var _material_floor_fire: StandardMaterial3D
var _material_floor_blind: StandardMaterial3D
var _material_wall: StandardMaterial3D
var _material_link: StandardMaterial3D
var _material_blocked: StandardMaterial3D
var _material_prop: StandardMaterial3D
var _material_camera: StandardMaterial3D
var _material_ceiling: StandardMaterial3D


func _ready() -> void:
	_build_materials()
	_build_rooms()
	_build_links()
	_build_props()
	_build_cameras()
	_build_overview_camera()


# --- 对外查询（供编辑器/验证脚本使用） ---------------------------------------

func get_camera_nodes() -> Dictionary:
	return _cameras.duplicate()


func get_room_names() -> Array:
	return _rooms.keys()


func get_room_display_name(room_id: String) -> String:
	return String(_room_by_id(room_id).get("name", room_id))


func get_map_summary() -> Dictionary:
	var camera_info: Array[Dictionary] = []
	for id in _cameras:
		var camera := _cameras[id].get_node("Camera3D") as Camera3D
		camera_info.append({
			"id": id,
			"room": String(_cameras[id].get_meta("room", "")),
			"position": _cameras[id].global_position,
			"fov": camera.fov,
		})
	var blind_rooms: Array[String] = []
	for room in ROOMS:
		if room.kind == "blind":
			blind_rooms.append(String(room.name))
	return {
		"rooms": _rooms.size(),
		"room_names": get_room_names(),
		"cameras": camera_info,
		"blind_rooms": blind_rooms,
		"plan_size": _plan_size(),
	}


# --- 材质 --------------------------------------------------------------------

func _build_materials() -> void:
	_material_floor_normal = _standard(Color(0.15, 0.16, 0.19))
	_material_floor_fire = _standard(Color(0.34, 0.15, 0.11), 0.7)
	_material_floor_blind = _standard(Color(0.11, 0.12, 0.14))
	_material_wall = _standard(Color(0.34, 0.36, 0.41), 0.9)
	_material_link = _standard(Color(0.26, 0.28, 0.33))
	_material_blocked = _standard(Color(0.62, 0.16, 0.18), 0.5)
	_material_prop = _standard(Color(0.28, 0.3, 0.35), 1.0)
	# 天花板单独一层：俯视相机裁剪掉，室内摄像头（如监控画面）能看到。
	_material_ceiling = _standard(Color(0.2, 0.21, 0.24), 1.0)
	_material_camera = _standard(Color(0.2, 0.9, 0.85), 0.4, 0.2)
	_material_camera.emission_enabled = true
	_material_camera.emission = Color(0.15, 0.85, 0.8)
	_material_camera.emission_energy_multiplier = 1.4


func _standard(color: Color, roughness := 0.85, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


# --- 房间 --------------------------------------------------------------------

func _build_rooms() -> void:
	for room in ROOMS:
		var rect: Rect2 = room.rect
		var node := Node3D.new()
		node.name = "Room_" + String(room.id)
		add_child(node)
		_rooms[room.id] = node

		var floor_material := _floor_material(String(room.kind))
		_add_box(node, "Floor",
			Vector3(rect.size.x, FLOOR_THICKNESS, rect.size.y),
			Vector3(rect.position.x + rect.size.x * 0.5, -FLOOR_THICKNESS * 0.5, rect.position.y + rect.size.y * 0.5),
			floor_material)
		var ceiling := _add_box(node, "Ceiling",
			Vector3(rect.size.x, 0.08, rect.size.y),
			Vector3(rect.position.x + rect.size.x * 0.5, WALL_HEIGHT + 0.04, rect.position.y + rect.size.y * 0.5),
			_material_ceiling)
		ceiling.layers = CEILING_LAYER
		_build_walls(room, node)
		_add_room_label(room, node)


func _floor_material(kind: String) -> StandardMaterial3D:
	match kind:
		"fire":
			return _material_floor_fire
		"blind":
			return _material_floor_blind
		_:
			return _material_floor_normal


func _build_walls(room: Dictionary, parent: Node3D) -> void:
	var rect: Rect2 = room.rect
	for side in ["north", "south", "west", "east"]:
		var link_kind := _link_kind_on_side(room, side)
		var closed := link_kind != "open"
		if not closed:
			continue
		var wall := _wall_geometry(rect, side)
		_add_box(parent, "Wall_" + side, wall.size, wall.position, _material_wall)


## 返回该房间某侧是否有连通（"open" / "blocked"），没有则返回 ""。
func _link_kind_on_side(room: Dictionary, side: String) -> String:
	var rect: Rect2 = room.rect
	for link in LINKS:
		if link.a != room.id and link.b != room.id:
			continue
		var other_id: String = link.b if link.a == room.id else link.a
		var other_rect: Rect2 = _room_by_id(other_id).rect
		if _is_on_side(rect, other_rect, side):
			return String(link.kind)
	return ""


func _is_on_side(rect: Rect2, other: Rect2, side: String) -> bool:
	var overlaps_x := maxf(rect.position.x, other.position.x) < minf(rect.end.x, other.end.x) - EPSILON
	var overlaps_z := maxf(rect.position.y, other.position.y) < minf(rect.end.y, other.end.y) - EPSILON
	match side:
		"north":
			return overlaps_x and other.end.y <= rect.position.y + EPSILON
		"south":
			return overlaps_x and other.position.y >= rect.end.y - EPSILON
		"west":
			return overlaps_z and other.end.x <= rect.position.x + EPSILON
		"east":
			return overlaps_z and other.position.x >= rect.end.x - EPSILON
	return false


func _wall_geometry(rect: Rect2, side: String) -> Dictionary:
	var thickness := WALL_THICKNESS
	var half := thickness * 0.5
	var height := WALL_HEIGHT * 0.5
	match side:
		"north":
			return {
				"size": Vector3(rect.size.x + thickness, WALL_HEIGHT, thickness),
				"position": Vector3(rect.position.x + rect.size.x * 0.5, height, rect.position.y),
			}
		"south":
			return {
				"size": Vector3(rect.size.x + thickness, WALL_HEIGHT, thickness),
				"position": Vector3(rect.position.x + rect.size.x * 0.5, height, rect.end.y),
			}
		"west":
			return {
				"size": Vector3(thickness, WALL_HEIGHT, rect.size.y + thickness),
				"position": Vector3(rect.position.x, height, rect.position.y + rect.size.y * 0.5),
			}
		_:
			return {
				"size": Vector3(thickness, WALL_HEIGHT, rect.size.y + thickness),
				"position": Vector3(rect.end.x, height, rect.position.y + rect.size.y * 0.5),
			}


# --- 通道 --------------------------------------------------------------------

func _build_links() -> void:
	var links_root := Node3D.new()
	links_root.name = "Links"
	add_child(links_root)
	for link in LINKS:
		var a: Rect2 = _room_by_id(String(link.a)).rect
		var b: Rect2 = _room_by_id(String(link.b)).rect
		var gap := _gap_rect(a, b)
		var center := gap.position + gap.size * 0.5
		if link.kind == "open":
			if gap.size.x > EPSILON and gap.size.y > EPSILON:
				_add_box(links_root, "Link_%s_%s" % [link.a, link.b],
					Vector3(maxf(gap.size.x, 1.2), FLOOR_THICKNESS, maxf(gap.size.y, 1.2)),
					Vector3(center.x, -FLOOR_THICKNESS * 0.5, center.y), _material_link)
		else:
			_add_box(links_root, "Blocked_%s_%s" % [link.a, link.b],
				Vector3(maxf(gap.size.x, 1.2), 0.08, maxf(gap.size.y, 1.2)),
				Vector3(center.x, 0.04, center.y), _material_blocked)
			_add_label(links_root, "堵死", Vector3(center.x, 0.9, center.y), 28, Color(0.95, 0.35, 0.35))


## 两矩形之间的空隙矩形（沿分离轴的距离 × 另一轴的重叠）。
func _gap_rect(a: Rect2, b: Rect2) -> Rect2:
	if a.end.x <= b.position.x + EPSILON:
		return Rect2(a.end.x, maxf(a.position.y, b.position.y), maxf(b.position.x - a.end.x, 0.0), _overlap_z(a, b))
	if b.end.x <= a.position.x + EPSILON:
		return Rect2(b.end.x, maxf(a.position.y, b.position.y), maxf(a.position.x - b.end.x, 0.0), _overlap_z(a, b))
	if a.end.y <= b.position.y + EPSILON:
		return Rect2(maxf(a.position.x, b.position.x), a.end.y, _overlap_x(a, b), maxf(b.position.y - a.end.y, 0.0))
	return Rect2(maxf(a.position.x, b.position.x), b.end.y, _overlap_x(a, b), maxf(a.position.y - b.end.y, 0.0))


func _overlap_x(a: Rect2, b: Rect2) -> float:
	return maxf(0.0, minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x))


func _overlap_z(a: Rect2, b: Rect2) -> float:
	return maxf(0.0, minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y))


# --- 占位道具 ----------------------------------------------------------------

func _build_props() -> void:
	_prop_lobby()
	_prop_seating()
	_prop_stage()
	_prop_backstage()
	_prop_prop_room()
	_prop_corridor()
	_prop_stairs()
	_prop_front_gate()


func _prop_lobby() -> void:
	var node := _rooms["lobby"] as Node3D
	var rect := _room_rect("lobby")
	_add_box(node, "ReceptionDesk", Vector3(2.4, 0.9, 0.7),
		Vector3(rect.position.x + rect.size.x * 0.5, 0.45, rect.position.y + rect.size.y * 0.55), _material_prop)
	_add_box(node, "Bench", Vector3(1.6, 0.45, 0.5),
		Vector3(rect.position.x + rect.size.x * 0.5, 0.22, rect.position.y + rect.size.y * 0.82), _material_prop)


func _prop_seating() -> void:
	var node := _rooms["seating"] as Node3D
	var rect := _room_rect("seating")
	var rows := 5
	var columns := 8
	var row_gap := (rect.size.y * 0.55) / float(rows)
	for row in range(rows):
		for column in range(columns):
			var x := rect.position.x + rect.size.x * 0.12 + column * (rect.size.x * 0.76 / float(columns - 1))
			var z := rect.position.y + rect.size.y * 0.2 + row * row_gap
			_add_box(node, "Seat_%d_%d" % [row, column], Vector3(0.5, 0.55, 0.45), Vector3(x, 0.27, z), _material_prop)


func _prop_stage() -> void:
	var node := _rooms["stage"] as Node3D
	var rect := _room_rect("stage")
	_add_box(node, "Platform", Vector3(rect.size.x * 0.86, 0.35, rect.size.y * 0.42),
		Vector3(rect.position.x + rect.size.x * 0.5, 0.17, rect.position.y + rect.size.y * 0.36), _material_prop)
	_add_box(node, "Speaker_L", Vector3(0.5, 0.9, 0.5),
		Vector3(rect.position.x + rect.size.x * 0.15, 0.45, rect.position.y + rect.size.y * 0.3), _material_prop)
	_add_box(node, "Speaker_R", Vector3(0.5, 0.9, 0.5),
		Vector3(rect.position.x + rect.size.x * 0.85, 0.45, rect.position.y + rect.size.y * 0.3), _material_prop)


func _prop_backstage() -> void:
	var node := _rooms["backstage"] as Node3D
	var rect := _room_rect("backstage")
	for index in range(3):
		_add_box(node, "Shelf_%d" % index, Vector3(1.0, 1.9, 2.2),
			Vector3(rect.position.x + rect.size.x * 0.72, 0.95, rect.position.y + rect.size.y * (0.25 + 0.2 * index)), _material_prop)


func _prop_prop_room() -> void:
	var node := _rooms["prop_room"] as Node3D
	var rect := _room_rect("prop_room")
	var offsets := [
		Vector2(0.2, 0.3), Vector2(0.4, 0.65), Vector2(0.55, 0.25),
		Vector2(0.7, 0.7), Vector2(0.82, 0.4), Vector2(0.62, 0.55),
	]
	for index in range(offsets.size()):
		var offset: Vector2 = offsets[index]
		_add_box(node, "Crate_%d" % index, Vector3(0.9, 0.9, 0.9),
			Vector3(rect.position.x + rect.size.x * offset.x, 0.45, rect.position.y + rect.size.y * offset.y), _material_prop)


func _prop_corridor() -> void:
	var node := _rooms["corridor"] as Node3D
	var rect := _room_rect("corridor")
	for index in range(2):
		_add_box(node, "Pillar_%d" % index, Vector3(0.5, 2.4, 0.5),
			Vector3(rect.position.x + rect.size.x * (0.35 + 0.3 * index), 1.2, rect.position.y + rect.size.y * 0.5), _material_prop)


func _prop_stairs() -> void:
	var node := _rooms["stairs"] as Node3D
	var rect := _room_rect("stairs")
	for index in range(6):
		_add_box(node, "Step_%d" % index, Vector3(rect.size.x * 0.86, 0.22, 0.5),
			Vector3(rect.position.x + rect.size.x * 0.5, 0.11 + index * 0.22, rect.position.y + rect.size.y * 0.2 + index * 0.55),
			_material_prop)


func _prop_front_gate() -> void:
	var node := _rooms["front_gate"] as Node3D
	var rect := _room_rect("front_gate")
	var center_x := rect.position.x + rect.size.x * 0.5
	# 被封死的正门：门框 + 堆叠的封堵物
	_add_box(node, "DoorFrame_L", Vector3(0.25, 2.2, 0.3), Vector3(center_x - 1.0, 1.1, rect.position.y + 0.25), _material_prop)
	_add_box(node, "DoorFrame_R", Vector3(0.25, 2.2, 0.3), Vector3(center_x + 1.0, 1.1, rect.position.y + 0.25), _material_prop)
	_add_box(node, "DoorFrame_Top", Vector3(2.25, 0.25, 0.3), Vector3(center_x, 2.2, rect.position.y + 0.25), _material_prop)
	for index in range(3):
		_add_box(node, "Barricade_%d" % index, Vector3(1.6, 0.6, 0.5),
			Vector3(center_x, 0.3 + index * 0.55, rect.position.y + 0.7), _material_prop)


# --- 摄像头 ------------------------------------------------------------------

func _build_cameras() -> void:
	var cameras_root := Node3D.new()
	cameras_root.name = "Cameras"
	add_child(cameras_root)
	for spec in CAMERAS:
		var rect := _room_rect(String(spec.room))
		var frac: Vector2 = spec.frac
		var position := Vector3(
			rect.position.x + rect.size.x * frac.x,
			CAMERA_HEIGHT,
			rect.position.y + rect.size.y * frac.y)
		var node := Node3D.new()
		node.name = String(spec.id)
		node.position = position
		node.set_meta("room", String(spec.room))
		cameras_root.add_child(node)

		_add_box(node, "Marker", Vector3(0.26, 0.26, 0.26), Vector3.ZERO, _material_camera)
		var camera := Camera3D.new()
		camera.name = "Camera3D"
		camera.fov = 70.0
		camera.current = false
		node.add_child(camera)
		var look_frac: Vector2 = spec.get("look", Vector2(0.5, 0.5))
		camera.look_at(Vector3(
			rect.position.x + rect.size.x * look_frac.x,
			0.0,
			rect.position.y + rect.size.y * look_frac.y), Vector3.UP)

		_add_label(cameras_root, String(spec.id),
			Vector3(position.x, CAMERA_HEIGHT + 0.55, position.z), 36, Color(0.35, 0.95, 0.9))
		_cameras[spec.id] = node


# --- 场景辅助 ----------------------------------------------------------------

func _build_overview_camera() -> void:
	var size := _plan_size()
	var center := _plan_center()
	var camera := Camera3D.new()
	camera.name = "OverviewCamera"
	camera.fov = 40.0
	camera.position = Vector3(center.x, 30.0, center.y)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.cull_mask = 1
	add_child(camera)
	camera.current = true


func _add_box(parent: Node3D, node_name: String, size: Vector3, center: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = center
	parent.add_child(instance)
	return instance


func _add_label(parent: Node3D, text: String, position: Vector3, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = "Label_" + text.replace("\n", "_")
	label.text = text
	label.position = position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = font_size
	label.pixel_size = 0.01
	label.outline_size = 8
	label.modulate = color
	parent.add_child(label)
	return label


func _add_room_label(room: Dictionary, parent: Node3D) -> void:
	var rect: Rect2 = room.rect
	var color := Color(0.92, 0.94, 0.98)
	match String(room.kind):
		"fire":
			color = Color(1.0, 0.62, 0.5)
		"blind":
			color = Color(0.72, 0.78, 0.85)
	var text := "%s\n%s" % [String(room.name), String(room.note)]
	_add_label(parent, text, Vector3(rect.position.x + rect.size.x * 0.5, 2.9, rect.position.y + rect.size.y * 0.5), 46, color)


func _room_by_id(room_id: String) -> Dictionary:
	for room in ROOMS:
		if room.id == room_id:
			return room
	return {}


func _room_rect(room_id: String) -> Rect2:
	return _room_by_id(room_id).rect


func _plan_size() -> Vector2:
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for room in ROOMS:
		var rect: Rect2 = room.rect
		min_point = Vector2(minf(min_point.x, rect.position.x), minf(min_point.y, rect.position.y))
		max_point = Vector2(maxf(max_point.x, rect.end.x), maxf(max_point.y, rect.end.y))
	return max_point - min_point


func _plan_center() -> Vector2:
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for room in ROOMS:
		var rect: Rect2 = room.rect
		min_point = Vector2(minf(min_point.x, rect.position.x), minf(min_point.y, rect.position.y))
		max_point = Vector2(maxf(max_point.x, rect.end.x), maxf(max_point.y, rect.end.y))
	return (min_point + max_point) * 0.5
