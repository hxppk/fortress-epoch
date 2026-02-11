class_name HeroBase
extends CharacterBody2D
## HeroBase — 英雄基类
## 处理移动、自动攻击委托、技能使用、面朝方向与 bobbing 动画。

# ============================================================
# 信号
# ============================================================

signal attack_performed(target: Node2D)
signal skill_used(skill_id: String)
signal hero_died()

# ============================================================
# 子节点引用
# ============================================================

@onready var stats: StatsComponent = $StatsComponent
@onready var sprite: Sprite2D = $Sprite2D
@onready var attack_area: Area2D = $AttackArea
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

# ============================================================
# 属性
# ============================================================

## 英雄 ID（如 "wolf_knight"）
@export var hero_id: String = ""

## 从 heroes.json 加载的完整数据
var hero_data: Dictionary = {}

## 所属玩家（预留多人）
var player_id: int = 0

## 移动方向（由外部控制器设置）
var move_direction: Vector2 = Vector2.ZERO

## 是否正在攻击
var is_attacking: bool = false

## 自动攻击计时器
var auto_attack_timer: float = 0.0

## 攻击范围内的敌人列表
var targets_in_range: Array = []

## 面朝方向（true = 右）
var facing_right: bool = true

# ============================================================
# 常量
# ============================================================

const HEROES_JSON_PATH: String = "res://data/heroes.json"

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	# 连接 AttackArea 信号
	attack_area.body_entered.connect(_on_attack_area_body_entered)
	attack_area.body_exited.connect(_on_attack_area_body_exited)

	# 连接 StatsComponent 死亡信号
	stats.died.connect(_on_stats_died)

	# 如果编辑器中已设置 hero_id，自动初始化
	if hero_id != "":
		initialize(hero_id)


func _physics_process(delta: float) -> void:
	if move_direction != Vector2.ZERO:
		var speed: float = stats.get_stat("speed")
		velocity = move_direction.normalized() * speed
		update_facing()
	else:
		velocity = Vector2.ZERO

	move_and_slide()


func _process(delta: float) -> void:
	# Bobbing 动画：仅在移动时生效
	if move_direction != Vector2.ZERO:
		var time_sec: float = Time.get_ticks_msec() / 1000.0
		sprite.position.y = sin(time_sec * 5.0) * 2.0
	else:
		# 停止移动时平滑归位
		sprite.position.y = lerpf(sprite.position.y, 0.0, delta * 10.0)

	# 自动攻击计时
	_process_auto_attack(delta)


func _draw() -> void:
	# 简单阴影：用多边形模拟椭圆
	_draw_shadow_ellipse(Vector2(0, 8), Vector2(6, 3), Color(0, 0, 0, 0.3))

# ============================================================
# 公有方法
# ============================================================

## 初始化英雄：加载数据、设置属性组件
func initialize(id: String) -> void:
	hero_id = id
	hero_data = _load_hero_data(id)
	if hero_data.is_empty():
		push_warning("HeroBase: 未找到英雄数据 id=%s" % id)
		return

	# 初始化 StatsComponent
	var base_stats_data: Dictionary = hero_data.get("base_stats", {})
	stats.initialize(base_stats_data)

	# 加载精灵纹理
	var sprite_path: String = hero_data.get("sprite", "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)

	# 根据数据设置攻击范围
	var attack_range: float = float(hero_data.get("base_stats", {}).get("attack_range", 40))
	_set_attack_range(attack_range)


## 设置移动方向（由外部 Controller 调用）
func set_move_direction(dir: Vector2) -> void:
	move_direction = dir


## 尝试自动攻击
func try_auto_attack() -> void:
	if targets_in_range.is_empty():
		return

	# 清理已失效的目标
	_clean_targets()
	if targets_in_range.is_empty():
		return

	# 获取最近的目标
	var target: Node2D = _get_nearest_target()
	if target == null:
		return

	# 执行攻击：根据英雄类型区分攻击模式
	var auto_attack_data: Dictionary = hero_data.get("auto_attack", {})
	var pattern: String = auto_attack_data.get("pattern", "single")

	match pattern:
		"fan_sweep":
			_perform_fan_attack(target, auto_attack_data)
		"aoe_impact":
			_perform_aoe_attack(target, auto_attack_data)
		_:
			_perform_single_attack(target)

	is_attacking = true
	attack_performed.emit(target)

	# 短暂标记攻击状态
	var tween: Tween = create_tween()
	tween.tween_callback(func() -> void: is_attacking = false).set_delay(0.2)


## 更新面朝方向
func update_facing() -> void:
	if move_direction.x > 0.01:
		facing_right = true
	elif move_direction.x < -0.01:
		facing_right = false
	sprite.flip_h = !facing_right

# ============================================================
# 信号回调
# ============================================================

func _on_attack_area_body_entered(body: Node2D) -> void:
	# 只追踪敌人（collision_mask 已经过滤了 layer 2）
	if body == self:
		return
	if not targets_in_range.has(body):
		targets_in_range.append(body)


func _on_attack_area_body_exited(body: Node2D) -> void:
	targets_in_range.erase(body)


func _on_stats_died() -> void:
	hero_died.emit()
	# 禁用物理处理
	set_physics_process(false)
	set_process(false)
	# 播放死亡视觉效果（简单淡出）
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)

# ============================================================
# 私有方法
# ============================================================

## 从 JSON 文件加载英雄数据
func _load_hero_data(id: String) -> Dictionary:
	if not FileAccess.file_exists(HEROES_JSON_PATH):
		push_error("HeroBase: heroes.json 不存在: %s" % HEROES_JSON_PATH)
		return {}

	var file: FileAccess = FileAccess.open(HEROES_JSON_PATH, FileAccess.READ)
	var json_text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_text)
	if parse_result != OK:
		push_error("HeroBase: heroes.json 解析失败: %s" % json.get_error_message())
		return {}

	var data: Dictionary = json.data
	var heroes_array: Array = data.get("heroes", [])

	for hero: Dictionary in heroes_array:
		if hero.get("id", "") == id:
			return hero

	return {}


## 自动攻击计时处理
func _process_auto_attack(delta: float) -> void:
	if hero_data.is_empty():
		return

	var attack_speed: float = stats.get_stat("attack_speed")
	if attack_speed <= 0.0:
		return

	var attack_interval: float = 1.0 / attack_speed
	auto_attack_timer += delta

	if auto_attack_timer >= attack_interval:
		auto_attack_timer -= attack_interval
		try_auto_attack()


## 设置攻击范围（Area2D 内的 CollisionShape2D 半径）
func _set_attack_range(radius: float) -> void:
	var attack_range_shape: CollisionShape2D = attack_area.get_node("AttackRange")
	if attack_range_shape and attack_range_shape.shape is CircleShape2D:
		attack_range_shape.shape = attack_range_shape.shape.duplicate()
		attack_range_shape.shape.radius = radius


## 清理失效目标（已被销毁或已死亡）
func _clean_targets() -> void:
	for i in range(targets_in_range.size() - 1, -1, -1):
		var target: Node2D = targets_in_range[i]
		if not is_instance_valid(target) or not target.is_inside_tree():
			targets_in_range.remove_at(i)
			continue
		# 如果目标有 StatsComponent，检查是否存活
		if target.has_node("StatsComponent"):
			var target_stats: StatsComponent = target.get_node("StatsComponent")
			if not target_stats.is_alive():
				targets_in_range.remove_at(i)


## 获取最近的目标
func _get_nearest_target() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = INF

	for target: Node2D in targets_in_range:
		if not is_instance_valid(target):
			continue
		var dist: float = global_position.distance_squared_to(target.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = target

	return nearest


## 扇形攻击（如狼骑士普攻）
func _perform_fan_attack(primary_target: Node2D, attack_data: Dictionary) -> void:
	var fan_angle_deg: float = float(attack_data.get("angle", 120))
	var fan_angle_rad: float = deg_to_rad(fan_angle_deg)
	var attack_value: float = stats.get_stat("attack")
	var hit_count: int = 0

	# 计算攻击朝向：朝向最近目标
	var attack_dir: Vector2 = (primary_target.global_position - global_position).normalized()

	for target: Node2D in targets_in_range:
		if not is_instance_valid(target):
			continue
		var to_target: Vector2 = (target.global_position - global_position).normalized()
		var angle: float = attack_dir.angle_to(to_target)

		# 在扇形角度范围内的目标受到伤害
		if absf(angle) <= fan_angle_rad / 2.0:
			_deal_damage_to(target, attack_value)
			hit_count += 1

	# 检查命中阈值效果（如白狼骑士命中 3+ 获得攻速加成）
	var threshold: int = int(attack_data.get("hit_count_threshold", 0))
	if threshold > 0 and hit_count >= threshold:
		var effect_type: String = attack_data.get("on_threshold_effect", "")
		_apply_threshold_effect(effect_type)


## AOE 攻击（如流星法师普攻）
func _perform_aoe_attack(primary_target: Node2D, attack_data: Dictionary) -> void:
	var aoe_radius: float = float(attack_data.get("radius", 32))
	var attack_value: float = stats.get_stat("attack")
	var spell_power: float = stats.get_stat("spell_power")
	# 法师的伤害 = attack + spell_power
	var total_damage: float = attack_value + spell_power

	# 对落点范围内的所有目标造成伤害
	var impact_pos: Vector2 = primary_target.global_position

	for target: Node2D in targets_in_range:
		if not is_instance_valid(target):
			continue
		var dist: float = impact_pos.distance_to(target.global_position)
		if dist <= aoe_radius:
			_deal_damage_to(target, total_damage)


## 单体攻击（默认）
func _perform_single_attack(target: Node2D) -> void:
	var attack_value: float = stats.get_stat("attack")
	_deal_damage_to(target, attack_value)


## 对目标造成伤害
func _deal_damage_to(target: Node2D, raw_damage: float) -> void:
	if not is_instance_valid(target):
		return

	# 暴击判定
	var crit_rate: float = stats.get_stat("crit_rate")
	var is_crit: bool = randf() < crit_rate
	var final_damage: float = raw_damage * (1.5 if is_crit else 1.0)

	# 目标防御减伤
	if target.has_node("StatsComponent"):
		var target_stats: StatsComponent = target.get_node("StatsComponent")
		var defense: float = target_stats.get_stat("defense")
		# 简单减伤公式：实际伤害 = damage * (100 / (100 + defense))
		final_damage = final_damage * (100.0 / (100.0 + defense))
		target_stats.take_damage(final_damage)

	# 记录伤害到 GameManager（如果存在）
	var game_manager: Node = Engine.get_singleton("GameManager") if Engine.has_singleton("GameManager") else null
	if game_manager == null and has_node("/root/GameManager"):
		game_manager = get_node("/root/GameManager")
	if game_manager and game_manager.has_method("record_damage"):
		game_manager.record_damage(final_damage)


## 应用阈值效果
func _apply_threshold_effect(effect_type: String) -> void:
	match effect_type:
		"attack_speed_boost":
			# 临时攻速加成 30%，持续 3 秒
			var boost_value: float = stats.get_stat("attack_speed") * 0.3
			stats.add_modifier("attack_speed", "fan_threshold_boost", boost_value)
			# 定时移除
			get_tree().create_timer(3.0).timeout.connect(
				func() -> void:
					stats.remove_modifier("attack_speed", "fan_threshold_boost")
			)


## 绘制椭圆阴影（用多边形模拟）
func _draw_shadow_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var point_count: int = 24
	var points: PackedVector2Array = PackedVector2Array()

	for i in range(point_count):
		var angle: float = TAU * float(i) / float(point_count)
		var point: Vector2 = center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		points.append(point)

	draw_colored_polygon(points, color)
