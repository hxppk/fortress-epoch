class_name AutoAttackComponent
extends Node
## AutoAttackComponent -- 英雄和塔共用的自动攻击组件
## 支持单体、扇形、AOE 三种攻击模式。

# ============================================================
# 信号
# ============================================================

signal attack_performed(targets: Array, damage: int)
signal threshold_reached(effect: String)

# ============================================================
# 导出变量
# ============================================================

## 攻击模式："single_target" | "fan_sweep" | "aoe_impact"
@export var attack_pattern: String = "single_target"

## 扇形角度（fan_sweep 用）
@export var fan_angle: float = 120.0

## AOE 半径（aoe_impact 用）
@export var aoe_radius: float = 32.0

## 连击阈值（白狼骑士为 3）
@export var hit_count_threshold: int = 0

## 达到阈值时触发的效果名
@export var threshold_effect: String = ""

# ============================================================
# 属性
# ============================================================

## 所有者节点（英雄或塔）
var owner_node: Node2D = null

## 所有者的属性组件
var stats: StatsComponent = null

## 攻击计时器（秒）
var attack_timer: float = 0.0

## 攻击范围内的目标列表
var targets_in_range: Array[Node2D] = []

## 当前连击计数
var hit_count: int = 0

## 攻击范围 Area2D（从父节点获取）
var attack_area: Area2D = null

# ============================================================
# 初始化
# ============================================================

## 初始化组件，绑定所有者、属性组件和 Area2D。
func initialize(owner: Node2D, stats_comp: StatsComponent, area: Area2D) -> void:
	owner_node = owner
	stats = stats_comp
	attack_area = area

	if attack_area:
		# 避免重复连接信号
		if not attack_area.body_entered.is_connected(_on_body_entered):
			attack_area.body_entered.connect(_on_body_entered)
		if not attack_area.body_exited.is_connected(_on_body_exited):
			attack_area.body_exited.connect(_on_body_exited)

# ============================================================
# 帧处理
# ============================================================

func _process(delta: float) -> void:
	if owner_node == null or stats == null:
		return

	if not stats.is_alive():
		return

	var attack_speed: float = stats.get_stat("attack_speed")
	if attack_speed <= 0.0:
		return

	var attack_interval: float = 1.0 / attack_speed
	attack_timer += delta

	if attack_timer >= attack_interval:
		attack_timer -= attack_interval
		try_attack()

# ============================================================
# 攻击逻辑
# ============================================================

## 尝试执行一次攻击
func try_attack() -> void:
	# 清理失效目标
	_clean_targets()
	if targets_in_range.is_empty():
		return

	match attack_pattern:
		"single_target":
			_attack_single_target()
		"fan_sweep":
			_attack_fan_sweep()
		"aoe_impact":
			_attack_aoe_impact()
		_:
			_attack_single_target()


## 单体攻击：塔用，攻击最近的一个敌人
func _attack_single_target() -> void:
	var target: Node2D = _get_nearest_target()
	if target == null:
		return

	var atk: float = stats.get_stat("attack")
	var damage: int = _calculate_and_apply_damage(target, atk)

	# 单体攻击连线特效
	_spawn_single_vfx(owner_node.global_position, target.global_position)

	hit_count += 1
	_check_threshold()
	attack_performed.emit([target], damage)


## 扇形攻击：白狼骑士，扇形范围内所有敌人
func _attack_fan_sweep() -> void:
	var primary: Node2D = _get_nearest_target()
	if primary == null:
		return

	var center: Vector2 = owner_node.global_position
	var direction: Vector2 = (primary.global_position - center).normalized()
	var atk: float = stats.get_stat("attack")
	var attack_range: float = stats.get_stat("attack_range")

	var hit_targets: Array = _get_enemies_in_fan(center, direction, fan_angle, attack_range)
	var total_damage: int = 0

	for target: Node2D in hit_targets:
		var dmg: int = _calculate_and_apply_damage(target, atk)
		total_damage += dmg

	# 扇形斩击特效
	_spawn_fan_vfx(center, direction, attack_range)

	hit_count += hit_targets.size()
	_check_threshold()
	attack_performed.emit(hit_targets, total_damage)


## AOE 攻击：流星法师，选择目标点，AOE 伤害
func _attack_aoe_impact() -> void:
	var primary: Node2D = _get_nearest_target()
	if primary == null:
		return

	var impact_pos: Vector2 = primary.global_position
	var atk: float = stats.get_stat("attack")
	var spell_power: float = stats.get_stat("spell_power")
	var total_raw: float = atk + spell_power

	var hit_targets: Array = []
	var total_damage: int = 0

	for target: Node2D in targets_in_range:
		if not is_instance_valid(target):
			continue
		var dist: float = impact_pos.distance_to(target.global_position)
		if dist <= aoe_radius:
			var dmg: int = _calculate_and_apply_damage(target, total_raw)
			total_damage += dmg
			hit_targets.append(target)

			# 流星法师被动：星火燎原（AOE 命中触发灼烧）
			if owner_node and owner_node.has_method("trigger_starfire_spread"):
				owner_node.trigger_starfire_spread(target)

	# AOE 圈特效
	_spawn_aoe_vfx(impact_pos)

	hit_count += hit_targets.size()
	_check_threshold()
	attack_performed.emit(hit_targets, total_damage)

# ============================================================
# 扇形范围检测
# ============================================================

## 获取扇形范围内的敌人
func _get_enemies_in_fan(center: Vector2, direction: Vector2, angle: float, radius: float) -> Array:
	var result: Array = []
	var half_angle_rad: float = deg_to_rad(angle / 2.0)

	for target: Node2D in targets_in_range:
		if not is_instance_valid(target):
			continue
		var to_target: Vector2 = target.global_position - center
		var dist: float = to_target.length()
		if dist > radius:
			continue
		var angle_to: float = direction.angle_to(to_target.normalized())
		if absf(angle_to) <= half_angle_rad:
			result.append(target)

	return result

# ============================================================
# Area2D 回调
# ============================================================

## 敌人进入攻击范围
func _on_body_entered(body: Node2D) -> void:
	if body == owner_node:
		return
	# 只追踪拥有 StatsComponent 的活着的实体
	if body.has_node("StatsComponent"):
		var body_stats: StatsComponent = body.get_node("StatsComponent")
		if body_stats.is_alive() and not targets_in_range.has(body):
			targets_in_range.append(body)


## 敌人离开攻击范围
func _on_body_exited(body: Node2D) -> void:
	targets_in_range.erase(body)

# ============================================================
# 连击阈值
# ============================================================

## 检查连击阈值，达到时触发效果并重置计数
func _check_threshold() -> void:
	if hit_count_threshold <= 0:
		return
	if threshold_effect == "":
		return

	if hit_count >= hit_count_threshold:
		hit_count = 0
		_apply_threshold_effect(threshold_effect)
		threshold_reached.emit(threshold_effect)


## 应用阈值效果
func _apply_threshold_effect(effect_name: String) -> void:
	if stats == null:
		return

	match effect_name:
		"attack_speed_boost":
			# 临时攻速加成 30%，持续 3 秒
			var boost_value: float = stats.get_stat("attack_speed") * 0.3
			stats.add_modifier("attack_speed", "threshold_atk_spd_boost", boost_value)
			# 定时移除
			if owner_node and owner_node.is_inside_tree():
				owner_node.get_tree().create_timer(3.0).timeout.connect(
					func() -> void:
						if stats and is_instance_valid(owner_node):
							stats.remove_modifier("attack_speed", "threshold_atk_spd_boost")
				)
		"damage_boost":
			# 临时攻击加成 20%，持续 3 秒
			var boost_value: float = stats.get_stat("attack") * 0.2
			stats.add_modifier("attack", "threshold_atk_boost", boost_value)
			if owner_node and owner_node.is_inside_tree():
				owner_node.get_tree().create_timer(3.0).timeout.connect(
					func() -> void:
						if stats and is_instance_valid(owner_node):
							stats.remove_modifier("attack", "threshold_atk_boost")
				)

# ============================================================
# 伤害计算（内置安全计算）
# ============================================================

## 计算并应用伤害，返回实际伤害值。
## 优先使用 DamageSystem Autoload，不存在时使用内置公式。
func _calculate_and_apply_damage(target: Node2D, raw_atk: float) -> int:
	if not is_instance_valid(target):
		return 0

	var target_stats: StatsComponent = null
	if target.has_node("StatsComponent"):
		target_stats = target.get_node("StatsComponent")
	if target_stats == null:
		return 0

	# 使用 DamageSystem Autoload
	var damage_system: Node = DamageSystem

	if damage_system and damage_system.has_method("calculate_damage"):
		var damage_info: Dictionary = damage_system.calculate_damage(stats, target_stats)
		if damage_system.has_method("apply_damage"):
			damage_system.apply_damage(owner_node, target, damage_info)
		else:
			target_stats.take_damage(float(damage_info["damage"]))
		return int(damage_info["damage"])

	# 内置安全公式：max(atk - def, 1)
	var defense: float = target_stats.get_stat("defense")
	var crit_rate: float = stats.get_stat("crit_rate")
	var base_damage: int = maxi(int(raw_atk - defense), 1)
	var is_crit: bool = randf() < crit_rate
	if is_crit:
		base_damage *= 2
	target_stats.take_damage(float(base_damage))
	return base_damage

# ============================================================
# 工具方法
# ============================================================

## 获取最近的目标
func _get_nearest_target() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = INF

	for target: Node2D in targets_in_range:
		if not is_instance_valid(target):
			continue
		var dist: float = owner_node.global_position.distance_squared_to(target.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = target

	return nearest


## 清理失效目标（已销毁或已死亡）
func _clean_targets() -> void:
	for i in range(targets_in_range.size() - 1, -1, -1):
		var target: Node2D = targets_in_range[i]
		if not is_instance_valid(target) or not target.is_inside_tree():
			targets_in_range.remove_at(i)
			continue
		if target.has_node("StatsComponent"):
			var target_stats: StatsComponent = target.get_node("StatsComponent")
			if not target_stats.is_alive():
				targets_in_range.remove_at(i)

# ============================================================
# 攻击视觉特效
# ============================================================

## 扇形斩击弧线特效
func _spawn_fan_vfx(center: Vector2, direction: Vector2, radius: float) -> void:
	var vfx := _FanSlashVFX.new()
	vfx.center = center
	vfx.direction = direction
	vfx.radius = radius
	vfx.angle = fan_angle
	vfx.z_index = 50
	var scene_root := owner_node.get_tree().current_scene
	if scene_root:
		scene_root.add_child(vfx)


## AOE 冲击圈特效
func _spawn_aoe_vfx(impact_pos: Vector2) -> void:
	var vfx := _AoeCircleVFX.new()
	vfx.center = impact_pos
	vfx.radius = aoe_radius
	vfx.z_index = 50
	var scene_root := owner_node.get_tree().current_scene
	if scene_root:
		scene_root.add_child(vfx)


## 单体攻击连线特效
func _spawn_single_vfx(from_pos: Vector2, to_pos: Vector2) -> void:
	var vfx := _SlashLineVFX.new()
	vfx.from_pos = from_pos
	vfx.to_pos = to_pos
	vfx.z_index = 50
	var scene_root := owner_node.get_tree().current_scene
	if scene_root:
		scene_root.add_child(vfx)


# ============================================================
# 内部 VFX 类
# ============================================================

## 扇形弧线 — 白色半透明扇形快速闪现
class _FanSlashVFX extends Node2D:
	var center: Vector2
	var direction: Vector2
	var radius: float
	var angle: float
	var lifetime: float = 0.2
	var age: float = 0.0

	func _ready() -> void:
		global_position = Vector2.ZERO

	func _process(delta: float) -> void:
		age += delta
		if age >= lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var alpha: float = 1.0 - (age / lifetime)
		var color := Color(1.0, 1.0, 1.0, 0.5 * alpha)
		var outline_color := Color(1.0, 0.9, 0.3, 0.8 * alpha)
		var half_angle: float = deg_to_rad(angle / 2.0)
		var base_angle: float = direction.angle()
		var points: PackedVector2Array = [center]
		var segments: int = 12
		for i in range(segments + 1):
			var t: float = float(i) / float(segments)
			var a: float = base_angle - half_angle + t * half_angle * 2.0
			points.append(center + Vector2(cos(a), sin(a)) * radius)
		# 填充扇形
		if points.size() >= 3:
			var colors: PackedColorArray = []
			for i in range(points.size()):
				colors.append(color)
			draw_polygon(points, colors)
		# 弧线描边
		for i in range(1, points.size() - 1):
			draw_line(points[i], points[i + 1], outline_color, 1.5)


## AOE 圈 — 橙红色扩散圈
class _AoeCircleVFX extends Node2D:
	var center: Vector2
	var radius: float
	var lifetime: float = 0.3
	var age: float = 0.0

	func _ready() -> void:
		global_position = Vector2.ZERO

	func _process(delta: float) -> void:
		age += delta
		if age >= lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var progress: float = age / lifetime
		var current_radius: float = radius * (0.3 + 0.7 * progress)
		var alpha: float = 0.6 * (1.0 - progress)
		var fill_color := Color(1.0, 0.4, 0.1, alpha * 0.4)
		var ring_color := Color(1.0, 0.6, 0.2, alpha)
		# 填充圆
		draw_circle(center, current_radius, fill_color)
		# 描边圆
		var segments: int = 24
		var prev: Vector2 = center + Vector2(current_radius, 0)
		for i in range(1, segments + 1):
			var a: float = TAU * float(i) / float(segments)
			var next: Vector2 = center + Vector2(cos(a), sin(a)) * current_radius
			draw_line(prev, next, ring_color, 1.5)
			prev = next


## 单体斩线 — 快速白色直线
class _SlashLineVFX extends Node2D:
	var from_pos: Vector2
	var to_pos: Vector2
	var lifetime: float = 0.15
	var age: float = 0.0

	func _ready() -> void:
		global_position = Vector2.ZERO

	func _process(delta: float) -> void:
		age += delta
		if age >= lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var alpha: float = 1.0 - (age / lifetime)
		var color := Color(1.0, 1.0, 1.0, 0.7 * alpha)
		draw_line(from_pos, to_pos, color, 2.0)
