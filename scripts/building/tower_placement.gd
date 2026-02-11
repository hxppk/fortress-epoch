class_name TowerPlacement
extends Node2D
## TowerPlacement — 网格化建筑放置系统
## 管理建筑预览、网格吸附、放置合法性检查与建筑实例化。

# ============================================================
# 信号
# ============================================================

signal building_placed(building: BuildingBase, grid_pos: Vector2i)
signal placement_cancelled()

# ============================================================
# 常量
# ============================================================

## 网格尺寸（像素）
const GRID_SIZE: int = 16

## 建筑场景路径映射
const BUILDING_SCENES: Dictionary = {
	"arrow_tower": "res://scenes/entities/buildings/arrow_tower.tscn",
	"gold_mine": "res://scenes/entities/buildings/gold_mine.tscn",
	"barracks": "res://scenes/entities/buildings/barracks.tscn",
}

## buildings.json 路径
const BUILDINGS_JSON_PATH: String = "res://data/buildings.json"

# ============================================================
# 属性
# ============================================================

## 是否在放置模式
var is_placing: bool = false

## 当前要放置的建筑类型
var current_building_type: String = ""

## 放置预览（半透明精灵）
var ghost_building: Sprite2D = null

## 已占用的格子 { Vector2i: BuildingBase }
var occupied_cells: Dictionary = {}

## 可放置区域（网格坐标范围）
var placeable_area: Rect2i = Rect2i(0, 0, 60, 40)

## 所有已放置建筑
var buildings: Array[BuildingBase] = []

## 缓存的建筑数据（从 JSON 加载）
var _buildings_data: Dictionary = {}

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	_load_buildings_json()


func _process(_delta: float) -> void:
	if is_placing and ghost_building:
		_update_ghost_position()


func _unhandled_input(event: InputEvent) -> void:
	if not is_placing:
		return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed:
			if mouse_event.button_index == MOUSE_BUTTON_LEFT:
				# 左键确认放置
				var world_pos: Vector2 = get_global_mouse_position()
				var grid_pos: Vector2i = _world_to_grid(world_pos)
				if _can_place_at(grid_pos):
					_place_building(grid_pos)
				get_viewport().set_input_as_handled()

			elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
				# 右键取消
				cancel_placement()
				get_viewport().set_input_as_handled()

# ============================================================
# 公有方法
# ============================================================

## 进入放置模式
func start_placement(building_type: String) -> void:
	if not BUILDING_SCENES.has(building_type):
		push_warning("TowerPlacement: 未知建筑类型 '%s'" % building_type)
		return

	# 检查建造费用是否足够
	var build_cost: Dictionary = _get_build_cost(building_type)
	var can_afford: bool = true
	for resource_type: String in build_cost:
		var amount: int = int(build_cost[resource_type])
		if not GameManager.resources.has(resource_type) or GameManager.resources[resource_type] < amount:
			can_afford = false
			break

	if not can_afford:
		push_warning("TowerPlacement: 资源不足，无法建造 '%s'" % building_type)
		return

	# 如果已在放置模式，先取消
	if is_placing:
		cancel_placement()

	current_building_type = building_type
	is_placing = true
	_create_ghost()


## 取消放置
func cancel_placement() -> void:
	if ghost_building:
		ghost_building.queue_free()
		ghost_building = null

	is_placing = false
	current_building_type = ""
	placement_cancelled.emit()


## 获取指定格子的建筑
func get_building_at(grid_pos: Vector2i) -> BuildingBase:
	if occupied_cells.has(grid_pos):
		return occupied_cells[grid_pos] as BuildingBase
	return null


## 移除建筑
func remove_building(grid_pos: Vector2i) -> void:
	if not occupied_cells.has(grid_pos):
		return

	var building: BuildingBase = occupied_cells[grid_pos] as BuildingBase
	occupied_cells.erase(grid_pos)
	buildings.erase(building)

	if is_instance_valid(building):
		building.queue_free()

# ============================================================
# 私有方法 — 坐标转换
# ============================================================

## 世界坐标转网格坐标
func _world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floorf(world_pos.x / float(GRID_SIZE))),
		int(floorf(world_pos.y / float(GRID_SIZE)))
	)


## 网格坐标转世界坐标（返回格子中心）
func _grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		float(grid_pos.x) * float(GRID_SIZE) + float(GRID_SIZE) / 2.0,
		float(grid_pos.y) * float(GRID_SIZE) + float(GRID_SIZE) / 2.0
	)

# ============================================================
# 私有方法 — 放置逻辑
# ============================================================

## 是否可以在此放置
func _can_place_at(grid_pos: Vector2i) -> bool:
	# 检查是否在可放置区域内
	if not placeable_area.has_point(grid_pos):
		return false

	# 检查是否已被占用
	if occupied_cells.has(grid_pos):
		return false

	return true


## 确认放置建筑
func _place_building(grid_pos: Vector2i) -> void:
	# 扣除建造费用
	var build_cost: Dictionary = _get_build_cost(current_building_type)
	for resource_type: String in build_cost:
		var amount: int = int(build_cost[resource_type])
		if not GameManager.spend_resource(resource_type, amount):
			push_warning("TowerPlacement: 放置时扣资源失败")
			cancel_placement()
			return

	# 实例化建筑场景
	var scene_path: String = BUILDING_SCENES[current_building_type]
	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		push_error("TowerPlacement: 无法加载场景 '%s'" % scene_path)
		cancel_placement()
		return

	var building: BuildingBase = scene.instantiate() as BuildingBase
	if building == null:
		push_error("TowerPlacement: 场景实例化失败 '%s'" % scene_path)
		cancel_placement()
		return

	# 添加到场景树
	add_child(building)

	# 放置到网格位置
	var world_pos: Vector2 = _grid_to_world(grid_pos)
	building.place_at(grid_pos, world_pos)

	# 记录占用
	occupied_cells[grid_pos] = building
	buildings.append(building)

	# 发射信号
	building_placed.emit(building, grid_pos)

	# 清理 ghost 并退出放置模式
	if ghost_building:
		ghost_building.queue_free()
		ghost_building = null

	is_placing = false
	current_building_type = ""

# ============================================================
# 私有方法 — Ghost 预览
# ============================================================

## 创建半透明预览
func _create_ghost() -> void:
	ghost_building = Sprite2D.new()

	# 尝试加载建筑精灵纹理
	var building_info: Dictionary = _get_building_info(current_building_type)
	var sprite_path: String = building_info.get("sprite", "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		ghost_building.texture = load(sprite_path)
	else:
		# 没有纹理时使用占位纹理（白色方块）
		var image: Image = Image.create(14, 14, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		ghost_building.texture = ImageTexture.create_from_image(image)

	ghost_building.modulate = Color(0.0, 1.0, 0.0, 0.5)  # 半透明绿色
	ghost_building.z_index = 100  # 确保在最上层
	add_child(ghost_building)


## 更新预览位置（跟随鼠标，吸附网格）
func _update_ghost_position() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var grid_pos: Vector2i = _world_to_grid(world_pos)
	var snapped_pos: Vector2 = _grid_to_world(grid_pos)
	ghost_building.global_position = snapped_pos

	# 根据是否可放置改变颜色
	if _can_place_at(grid_pos):
		ghost_building.modulate = Color(0.0, 1.0, 0.0, 0.5)  # 绿色 = 可放置
	else:
		ghost_building.modulate = Color(1.0, 0.0, 0.0, 0.5)  # 红色 = 不可放置

# ============================================================
# 私有方法 — 数据
# ============================================================

## 加载 buildings.json 数据
func _load_buildings_json() -> void:
	if not FileAccess.file_exists(BUILDINGS_JSON_PATH):
		push_error("TowerPlacement: buildings.json 不存在: %s" % BUILDINGS_JSON_PATH)
		return

	var file: FileAccess = FileAccess.open(BUILDINGS_JSON_PATH, FileAccess.READ)
	var json_text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_text)
	if parse_result != OK:
		push_error("TowerPlacement: buildings.json 解析失败: %s" % json.get_error_message())
		return

	_buildings_data = json.data


## 获取指定建筑的完整信息
func _get_building_info(building_type: String) -> Dictionary:
	var buildings_array: Array = _buildings_data.get("buildings", [])
	for building: Dictionary in buildings_array:
		if building.get("id", "") == building_type:
			return building
	return {}


## 获取建造费用（首次建造 = levels[0].upgrade_cost）
func _get_build_cost(building_type: String) -> Dictionary:
	var info: Dictionary = _get_building_info(building_type)
	if info.is_empty():
		return {}

	var levels: Array = info.get("levels", [])
	if levels.is_empty():
		return {}

	return levels[0].get("upgrade_cost", {})
