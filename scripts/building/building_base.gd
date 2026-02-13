class_name BuildingBase
extends StaticBody2D
## BuildingBase — 建筑基类
## 箭塔 / 金矿 / 兵营共用此脚本，通过 building_id 区分行为。

# ============================================================
# 信号
# ============================================================

signal building_placed(building: BuildingBase)
signal building_upgraded(building: BuildingBase, new_level: int)
signal resource_produced(type: String, amount: int)

# ============================================================
# 导出属性
# ============================================================

## 建筑类型 ID："arrow_tower" | "gold_mine" | "barracks"
@export var building_id: String = ""

## 当前等级（1-3）
@export var current_level: int = 1

# ============================================================
# 子节点引用
# ============================================================

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var attack_area: Area2D = $AttackArea
@onready var attack_range_shape: CollisionShape2D = $AttackArea/AttackRange
@onready var level_label: Label = $Label

# ============================================================
# 属性
# ============================================================

## 从 buildings.json 加载的完整建筑数据
var building_data: Dictionary = {}

## 当前等级的数据（levels 数组中的元素）
var level_data: Dictionary = {}

## 网格坐标
var grid_position: Vector2i = Vector2i.ZERO

## 是否已放置
var is_placed: bool = false

## 金矿产出计时器
var production_timer: float = 0.0

## 箭塔攻击计时器
var _attack_timer: float = 0.0

## 攻击范围内的目标列表（箭塔用）
var _targets_in_range: Array = []

# ============================================================
# 常量
# ============================================================

const BUILDINGS_JSON_PATH: String = "res://data/buildings.json"

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	# 连接 AttackArea 信号（箭塔用）
	attack_area.body_entered.connect(_on_attack_area_body_entered)
	attack_area.body_exited.connect(_on_attack_area_body_exited)

	# 如果编辑器中已设置 building_id，自动初始化
	if building_id != "":
		initialize(building_id)


func _process(delta: float) -> void:
	if not is_placed:
		return

	match building_id:
		"arrow_tower":
			_tower_attack(delta)
		"gold_mine":
			_mine_produce(delta)
		# barracks 不需要每帧逻辑，buff 在升级时一次性应用

# ============================================================
# 公有方法
# ============================================================

## 初始化建筑：加载数据、设置属性
func initialize(id: String) -> void:
	building_id = id
	building_data = _load_building_data(id)
	if building_data.is_empty():
		push_warning("BuildingBase: 未找到建筑数据 id=%s" % id)
		return

	_update_level_data()

	# 加载精灵纹理
	var sprite_path: String = building_data.get("sprite", "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)

	# 根据建筑类型配置 AttackArea
	if building_id == "arrow_tower":
		attack_area.monitoring = true
		attack_area.monitorable = true
		# 设置初始攻击范围
		var range_radius: float = float(level_data.get("range", 96))
		_set_attack_range(range_radius)
	else:
		# 金矿和兵营不需要攻击区域
		attack_area.monitoring = false
		attack_area.monitorable = false
		attack_range_shape.disabled = true


## 放置到指定位置
func place_at(grid_pos: Vector2i, world_pos: Vector2) -> void:
	grid_position = grid_pos
	global_position = world_pos
	is_placed = true
	production_timer = 0.0
	_attack_timer = 0.0

	# 兵营放置时立即应用 buff
	if building_id == "barracks":
		_barracks_buff()

	_update_label()
	building_placed.emit(self)


## 升级建筑，返回是否成功
func upgrade() -> bool:
	if not can_upgrade():
		return false

	# 扣除资源
	var cost: Dictionary = get_upgrade_cost()
	for resource_type: String in cost:
		var amount: int = int(cost[resource_type])
		if not GameManager.spend_resource(resource_type, amount):
			# 理论上 can_upgrade() 已检查过，此处为安全回退
			push_warning("BuildingBase: 升级扣资源失败 type=%s amount=%d" % [resource_type, amount])
			return false

	# 兵营升级前先移除旧 buff
	if building_id == "barracks":
		_remove_barracks_buff()

	current_level += 1
	_update_level_data()

	# 箭塔升级时更新攻击范围
	if building_id == "arrow_tower":
		var range_radius: float = float(level_data.get("range", 96))
		_set_attack_range(range_radius)

	# 兵营升级后重新应用 buff
	if building_id == "barracks":
		_barracks_buff()

	_update_label()
	building_upgraded.emit(self, current_level)
	return true


## 获取升级费用（下一级的 upgrade_cost）
func get_upgrade_cost() -> Dictionary:
	if building_data.is_empty():
		return {}

	var levels: Array = building_data.get("levels", [])
	# 升级到下一级需要的费用 = 下一级的 upgrade_cost
	var next_level_index: int = current_level  # current_level 从 1 开始，所以 index = current_level
	if next_level_index >= levels.size():
		return {}

	var next_level: Dictionary = levels[next_level_index]
	return next_level.get("upgrade_cost", {})


## 是否能升级（不超过 3 级 + 资源够）
func can_upgrade() -> bool:
	if current_level >= 3:
		return false

	var cost: Dictionary = get_upgrade_cost()
	if cost.is_empty():
		return false

	for resource_type: String in cost:
		var amount: int = int(cost[resource_type])
		if not GameManager.resources.has(resource_type):
			return false
		if GameManager.resources[resource_type] < amount:
			return false

	return true

# ============================================================
# 信号回调
# ============================================================

func _on_attack_area_body_entered(body: Node2D) -> void:
	if body == self:
		return
	if not _targets_in_range.has(body):
		_targets_in_range.append(body)


func _on_attack_area_body_exited(body: Node2D) -> void:
	_targets_in_range.erase(body)

# ============================================================
# 私有方法 — 建筑类型逻辑
# ============================================================

## 箭塔自动攻击逻辑
func _tower_attack(delta: float) -> void:
	if level_data.is_empty():
		return

	var attack_speed: float = float(level_data.get("attack_speed", 1.0))
	if attack_speed <= 0.0:
		return

	_attack_timer += delta
	if _attack_timer < attack_speed:
		return

	_attack_timer -= attack_speed

	# 清理失效目标
	_clean_targets()
	if _targets_in_range.is_empty():
		return

	# 寻找最近的敌人
	var nearest: Node2D = _get_nearest_target()
	if nearest == null:
		return

	# 造成伤害
	var damage: float = float(level_data.get("damage", 8))
	if nearest.has_node("StatsComponent"):
		var target_stats: StatsComponent = nearest.get_node("StatsComponent")
		target_stats.take_damage(damage)

	# 投射物视觉效果（方块从塔飞向敌人）
	_spawn_projectile(nearest, damage)


## 生成投射物视觉效果
func _spawn_projectile(target: Node2D, _damage: float) -> void:
	var projectile: ColorRect = ColorRect.new()
	projectile.custom_minimum_size = Vector2(4, 4)
	projectile.size = Vector2(4, 4)
	projectile.color = Color(1.0, 0.8, 0.2)  # 金黄色
	projectile.z_index = 10
	# 添加到场景树的最上层
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position - Vector2(2, 2)  # 居中偏移

	# 用 Tween 让投射物飞向目标
	var target_pos: Vector2 = target.global_position
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(projectile, "global_position", target_pos - Vector2(2, 2), 0.2)
	tween.tween_callback(projectile.queue_free)


## 金矿产出逻辑
func _mine_produce(delta: float) -> void:
	if level_data.is_empty():
		return

	var interval: float = float(level_data.get("production_interval", 10.0))
	if interval <= 0.0:
		return

	production_timer += delta
	if production_timer < interval:
		return

	production_timer -= interval

	# 产出金币
	var gold_amount: int = int(level_data.get("production", 5))
	GameManager.add_resource("gold", gold_amount)
	resource_produced.emit("gold", gold_amount)

	# Lv3 额外产出水晶
	if current_level >= 3:
		var crystal_chance: float = float(level_data.get("crystal_chance", 0.0))
		if crystal_chance > 0.0 and randf() < crystal_chance:
			GameManager.add_resource("crystal", 1)
			resource_produced.emit("crystal", 1)


## 兵营 buff 逻辑：给场景树中所有 HeroBase 添加属性修改器
func _barracks_buff() -> void:
	if level_data.is_empty():
		return

	var source_name: String = "barracks_lv%d" % current_level
	var heroes: Array[Node] = get_tree().get_nodes_in_group("heroes")

	# 如果英雄不在 group 中，遍历场景树查找
	if heroes.is_empty():
		heroes = _find_all_heroes()

	for hero_node: Node in heroes:
		if hero_node is HeroBase:
			var hero: HeroBase = hero_node as HeroBase
			var hero_stats: StatsComponent = hero.stats

			# 物理攻击加成
			var phys_bonus: float = float(level_data.get("phys_attack_bonus", 0))
			if phys_bonus > 0.0:
				hero_stats.add_modifier("attack", source_name, phys_bonus)

			# 魔法攻击加成
			var magic_bonus: float = float(level_data.get("magic_attack_bonus", 0))
			if magic_bonus > 0.0:
				hero_stats.add_modifier("spell_power", source_name, magic_bonus)

			# 生命值加成
			var hp_bonus: float = float(level_data.get("hp_bonus", 0))
			if hp_bonus > 0.0:
				hero_stats.add_modifier("hp", source_name, hp_bonus)

			# 护甲加成
			var armor_bonus: float = float(level_data.get("armor_bonus", 0))
			if armor_bonus > 0.0:
				hero_stats.add_modifier("defense", source_name, armor_bonus)


## 移除兵营旧 buff（升级前调用）
func _remove_barracks_buff() -> void:
	var source_name: String = "barracks_lv%d" % current_level
	var heroes: Array[Node] = get_tree().get_nodes_in_group("heroes")

	if heroes.is_empty():
		heroes = _find_all_heroes()

	for hero_node: Node in heroes:
		if hero_node is HeroBase:
			var hero: HeroBase = hero_node as HeroBase
			var hero_stats: StatsComponent = hero.stats
			hero_stats.remove_modifier("attack", source_name)
			hero_stats.remove_modifier("spell_power", source_name)
			hero_stats.remove_modifier("hp", source_name)
			hero_stats.remove_modifier("defense", source_name)

# ============================================================
# 私有方法 — 辅助
# ============================================================

## 更新当前等级数据
func _update_level_data() -> void:
	if building_data.is_empty():
		level_data = {}
		return

	var levels: Array = building_data.get("levels", [])
	var level_index: int = current_level - 1  # 等级从 1 开始，数组从 0 开始
	if level_index >= 0 and level_index < levels.size():
		level_data = levels[level_index].duplicate(true)  # 深拷贝，防止研究加成修改原始数据
	else:
		level_data = {}

	# 应用局外研究加成
	_apply_research_bonus()


## 应用研究加成到 level_data
func _apply_research_bonus() -> void:
	if level_data.is_empty() or building_id == "":
		return
	if not is_instance_valid(SaveManager):
		return

	var bonus: float = SaveManager.get_research_bonus(building_id)
	if bonus <= 0.0:
		return

	match building_id:
		"arrow_tower":
			if level_data.has("damage"):
				level_data["damage"] = roundi(float(level_data["damage"]) * (1.0 + bonus))
		"gold_mine":
			if level_data.has("production"):
				level_data["production"] = roundi(float(level_data["production"]) * (1.0 + bonus))
		"barracks":
			for key: String in ["phys_attack_bonus", "magic_attack_bonus", "hp_bonus", "armor_bonus"]:
				if level_data.has(key):
					level_data[key] = roundi(float(level_data[key]) * (1.0 + bonus))


## 更新等级标签
func _update_label() -> void:
	if level_label:
		level_label.text = "Lv%d" % current_level


## 设置攻击范围（修改 CircleShape2D 半径）
func _set_attack_range(radius: float) -> void:
	if attack_range_shape and attack_range_shape.shape is CircleShape2D:
		attack_range_shape.shape = attack_range_shape.shape.duplicate()
		attack_range_shape.shape.radius = radius


## 清理失效目标
func _clean_targets() -> void:
	for i in range(_targets_in_range.size() - 1, -1, -1):
		var target: Node2D = _targets_in_range[i]
		if not is_instance_valid(target) or not target.is_inside_tree():
			_targets_in_range.remove_at(i)
			continue
		if target.has_node("StatsComponent"):
			var target_stats: StatsComponent = target.get_node("StatsComponent")
			if not target_stats.is_alive():
				_targets_in_range.remove_at(i)


## 获取最近的目标
func _get_nearest_target() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = INF

	for target: Node2D in _targets_in_range:
		if not is_instance_valid(target):
			continue
		var dist: float = global_position.distance_squared_to(target.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = target

	return nearest


## 从场景树中查找所有 HeroBase 节点
func _find_all_heroes() -> Array[Node]:
	var result: Array[Node] = []
	_collect_heroes(get_tree().root, result)
	return result


## 递归收集 HeroBase 节点
func _collect_heroes(node: Node, result: Array[Node]) -> void:
	if node is HeroBase:
		result.append(node)
	for child: Node in node.get_children():
		_collect_heroes(child, result)


## 从 JSON 文件加载建筑数据
func _load_building_data(id: String) -> Dictionary:
	if not FileAccess.file_exists(BUILDINGS_JSON_PATH):
		push_error("BuildingBase: buildings.json 不存在: %s" % BUILDINGS_JSON_PATH)
		return {}

	var file: FileAccess = FileAccess.open(BUILDINGS_JSON_PATH, FileAccess.READ)
	var json_text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_text)
	if parse_result != OK:
		push_error("BuildingBase: buildings.json 解析失败: %s" % json.get_error_message())
		return {}

	var data: Dictionary = json.data
	var buildings_array: Array = data.get("buildings", [])

	for building: Dictionary in buildings_array:
		if building.get("id", "") == id:
			return building

	return {}
