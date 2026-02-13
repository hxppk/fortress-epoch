class_name EvilCastle
extends StaticBody2D
## EvilCastle — 邪恶城堡实体，出征模式攻击目标
## NPCs 需要摧毁这个城堡以获得胜利。

# ============================================================
# 信号
# ============================================================

signal castle_destroyed()
signal hp_changed(current: float, maximum: float)

# ============================================================
# 属性
# ============================================================

## 城堡的属性组件
var stats: StatsComponent = null

## 攻击力
var attack_power: float = 15.0

## 攻击范围
var attack_range: float = 120.0

## 攻击间隔（秒）
var attack_interval: float = 2.0

## 攻击计时器
var _attack_timer: float = 0.0

## 视觉节点
var _visual: ColorRect = null
var _label: Label = null
var _hp_bar: ProgressBar = null
var _collision_shape: CollisionShape2D = null

# ============================================================
# 初始化
# ============================================================

func _ready() -> void:
	# 设置碰撞层级：城堡在敌人层，不检测任何碰撞
	collision_layer = 2  # enemies
	collision_mask = 0

	# 添加到敌人组
	add_to_group("enemies")

	# 创建 StatsComponent
	stats = StatsComponent.new()
	stats.name = "StatsComponent"
	add_child(stats)


## 初始化城堡属性和视觉
func initialize(hp: float, atk: float, atk_range: float, atk_interval: float) -> void:
	attack_power = atk
	attack_range = atk_range
	attack_interval = atk_interval

	# 初始化属性组件
	stats.initialize({
		"hp": hp,
		"attack": atk,
		"defense": 0.0,
		"speed": 0.0,
		"attack_speed": 0.0,
		"crit_rate": 0.0,
		"attack_range": atk_range,
		"spell_power": 0.0
	})

	# 连接信号
	stats.died.connect(_on_stats_died)
	stats.health_changed.connect(_on_health_changed)

	# 创建碰撞形状
	_create_collision()

	# 创建视觉节点
	_create_visual()

	# 更新 HP 条
	_update_hp_bar()


func _create_collision() -> void:
	_collision_shape = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24.0, 40.0)
	_collision_shape.shape = shape
	add_child(_collision_shape)


func _create_visual() -> void:
	# 主体：深紫色矩形
	_visual = ColorRect.new()
	_visual.color = Color(0.3, 0.1, 0.4, 1.0)  # 深紫色
	_visual.size = Vector2(24.0, 40.0)
	_visual.position = Vector2(-12.0, -20.0)  # 居中
	_visual.z_index = 1
	add_child(_visual)

	# 标签："邪恶城堡"
	_label = Label.new()
	_label.text = "邪恶城堡"
	_label.position = Vector2(-20.0, -40.0)
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color.RED)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.z_index = 2
	add_child(_label)

	# HP 条
	_hp_bar = ProgressBar.new()
	_hp_bar.size = Vector2(40.0, 6.0)
	_hp_bar.position = Vector2(-20.0, -50.0)
	_hp_bar.show_percentage = false
	_hp_bar.z_index = 2

	# 设置 HP 条样式 (简单红色背景 + 绿色填充)
	var style_bg := StyleBoxFlat.new()
	style_bg.bg_color = Color(0.2, 0.0, 0.0, 0.8)
	_hp_bar.add_theme_stylebox_override("background", style_bg)

	var style_fill := StyleBoxFlat.new()
	style_fill.bg_color = Color(0.0, 0.8, 0.0, 0.9)
	_hp_bar.add_theme_stylebox_override("fill", style_fill)

	add_child(_hp_bar)


# ============================================================
# 更新逻辑
# ============================================================

func _process(delta: float) -> void:
	if stats == null or not stats.is_alive():
		return

	# 攻击计时
	_attack_timer += delta
	if _attack_timer >= attack_interval:
		_attack_timer = 0.0
		_try_attack()


func _try_attack() -> void:
	# 寻找攻击范围内最近的英雄
	var nearest_hero: Node2D = _find_nearest_hero()
	if nearest_hero == null:
		return

	# 检查距离
	var distance: float = global_position.distance_to(nearest_hero.global_position)
	if distance > attack_range:
		return

	# 使用 DamageSystem 正规伤害计算（含防御、暴击）
	var target_stats: StatsComponent = nearest_hero.get_node("StatsComponent") if nearest_hero.has_node("StatsComponent") else null
	if target_stats == null:
		return

	if DamageSystem and DamageSystem.has_method("calculate_damage"):
		var damage_info: Dictionary = DamageSystem.calculate_damage(stats, target_stats)
		DamageSystem.apply_damage(self, nearest_hero, damage_info)


func _find_nearest_hero() -> Node2D:
	var heroes: Array = get_tree().get_nodes_in_group("heroes")
	var nearest: Node2D = null
	var nearest_distance: float = INF

	for hero: Node in heroes:
		if not is_instance_valid(hero) or not hero is Node2D:
			continue

		# 检查是否有 StatsComponent 并且存活
		if not hero.has_node("StatsComponent"):
			continue

		var hero_stats: StatsComponent = hero.get_node("StatsComponent")
		if not hero_stats.is_alive():
			continue

		var distance: float = global_position.distance_to(hero.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = hero

	return nearest


# ============================================================
# 信号回调
# ============================================================

func _on_stats_died() -> void:
	castle_destroyed.emit()


func _on_health_changed(current_hp: float, max_hp: float) -> void:
	hp_changed.emit(current_hp, max_hp)
	_update_hp_bar()


func _update_hp_bar() -> void:
	if _hp_bar == null or stats == null:
		return

	_hp_bar.max_value = stats.max_hp
	_hp_bar.value = stats.current_hp
