class_name SkillSystem
extends Node
## SkillSystem -- 管理英雄主动技能 CD + 终极技蓄力
## 从 heroes.json 技能数据初始化，处理冷却、释放和效果执行。

# ============================================================
# 信号
# ============================================================

signal skill_used(skill_id: String)
signal skill_ready(skill_id: String)
signal ultimate_charged()
signal ultimate_used()
signal cooldown_updated(slot: int, remaining: float, total: float)

# ============================================================
# 属性
# ============================================================

## 所有者英雄节点
var hero: Node2D = null

## 技能字典 { skill_id: { "data": Dictionary, "cooldown_remaining": float, "cooldown_total": float, "is_ready": bool, "slot": int } }
var skills: Dictionary = {}

## 终极技蓄力进度
var ultimate_charge: float = 0.0

## 终极技满蓄力值（白狼 kill 50 / 法师 damage 3000）
var ultimate_max_charge: float = 50.0

## 终极技蓄力类型："kill_count" | "damage_dealt"
var ultimate_charge_type: String = "kill_count"

## 终极技数据
var ultimate_data: Dictionary = {}

## 英雄属性组件引用
var _stats: StatsComponent = null

## 英雄完整数据缓存
var _hero_data: Dictionary = {}

# ============================================================
# 初始化
# ============================================================

## 从英雄数据初始化技能系统
func initialize(hero_node: Node2D, hero_data: Dictionary) -> void:
	hero = hero_node
	_hero_data = hero_data

	# 获取 StatsComponent
	if hero.has_node("StatsComponent"):
		_stats = hero.get_node("StatsComponent")

	# 解析技能列表
	var skill_list: Array = hero_data.get("skills", [])
	skills.clear()
	ultimate_data = {}

	for skill: Dictionary in skill_list:
		var skill_type: String = skill.get("type", "")
		var skill_id: String = skill.get("id", "")

		match skill_type:
			"active":
				var slot: int = int(skill.get("slot", 0))
				var cooldown: float = float(skill.get("cooldown", 10.0))
				skills[skill_id] = {
					"data": skill,
					"cooldown_remaining": 0.0,
					"cooldown_total": cooldown,
					"is_ready": true,
					"slot": slot,
				}
			"ultimate":
				ultimate_data = skill
				var charge_cond: Dictionary = skill.get("charge_condition", {})
				ultimate_charge_type = charge_cond.get("type", "kill_count")
				ultimate_max_charge = float(charge_cond.get("value", 50))
				ultimate_charge = 0.0

	# 连接 GameManager 的统计信号用于终极技蓄力
	_connect_charge_signals()

# ============================================================
# 帧处理
# ============================================================

func _process(delta: float) -> void:
	if hero == null:
		return

	# 更新所有技能冷却
	for skill_id: String in skills:
		var skill_entry: Dictionary = skills[skill_id]
		if skill_entry["cooldown_remaining"] > 0.0:
			skill_entry["cooldown_remaining"] = maxf(skill_entry["cooldown_remaining"] - delta, 0.0)
			var slot: int = skill_entry["slot"]
			cooldown_updated.emit(slot, skill_entry["cooldown_remaining"], skill_entry["cooldown_total"])

			if skill_entry["cooldown_remaining"] <= 0.0 and not skill_entry["is_ready"]:
				skill_entry["is_ready"] = true
				skill_ready.emit(skill_id)

# ============================================================
# 技能可用性
# ============================================================

## 指定槽位的技能是否可用（slot 1 或 2）
func can_use_skill(slot: int) -> bool:
	for skill_id: String in skills:
		var entry: Dictionary = skills[skill_id]
		if entry["slot"] == slot:
			return entry["is_ready"]
	return false


## 释放指定槽位的技能
func use_skill(slot: int) -> void:
	for skill_id: String in skills:
		var entry: Dictionary = skills[skill_id]
		if entry["slot"] == slot and entry["is_ready"]:
			entry["is_ready"] = false
			entry["cooldown_remaining"] = entry["cooldown_total"]
			_execute_skill(entry["data"])
			skill_used.emit(skill_id)
			cooldown_updated.emit(slot, entry["cooldown_remaining"], entry["cooldown_total"])
			return

# ============================================================
# 技能执行分发
# ============================================================

## 执行具体技能效果
func _execute_skill(skill_data: Dictionary) -> void:
	var skill_id: String = skill_data.get("id", "")
	match skill_id:
		"wolf_rush":
			_execute_wolf_rush()
		"wolf_howl":
			_execute_wolf_howl()
		"meteor_shower":
			_execute_meteor_shower()
		"comet_strike":
			_execute_comet_strike()
		_:
			push_warning("SkillSystem: 未实现的技能 id=%s" % skill_id)

# ============================================================
# 终极技蓄力
# ============================================================

## 增加终极技蓄力值
func add_ultimate_charge(amount: float) -> void:
	if ultimate_data.is_empty():
		return

	var prev_charge: float = ultimate_charge
	ultimate_charge = minf(ultimate_charge + amount, ultimate_max_charge)

	# 蓄力刚满时发信号
	if prev_charge < ultimate_max_charge and ultimate_charge >= ultimate_max_charge:
		ultimate_charged.emit()


## 终极技是否可释放
func can_use_ultimate() -> bool:
	if ultimate_data.is_empty():
		return false
	return ultimate_charge >= ultimate_max_charge


## 释放终极技
func use_ultimate() -> void:
	if not can_use_ultimate():
		return

	ultimate_charge = 0.0

	var skill_id: String = ultimate_data.get("id", "")
	match skill_id:
		"wolf_form":
			_execute_wolf_form()
		"celestial_fall":
			_execute_celestial_fall()
		_:
			push_warning("SkillSystem: 未实现的终极技 id=%s" % skill_id)

	ultimate_used.emit()

# ============================================================
# 白狼骑士 -- 技能实现
# ============================================================

## 奔狼突袭：短距冲刺 + 路径伤害 + 减速
func _execute_wolf_rush() -> void:
	if hero == null or _stats == null:
		return

	var atk: float = _stats.get_stat("attack")
	var rush_damage: float = atk * 2.0
	var rush_distance: float = 80.0

	# 计算冲刺方向（面朝方向）
	var direction: Vector2 = Vector2.RIGHT
	if hero.has_method("get") and hero.get("facing_right") != null:
		direction = Vector2.RIGHT if hero.facing_right else Vector2.LEFT
	elif hero.has_method("get") and hero.get("move_direction") != null:
		if hero.move_direction != Vector2.ZERO:
			direction = hero.move_direction.normalized()

	var start_pos: Vector2 = hero.global_position
	var end_pos: Vector2 = start_pos + direction * rush_distance

	# 在冲刺前记录攻击范围内的敌人（路径上的）
	var enemies_on_path: Array = _get_enemies_on_path(start_pos, end_pos, 24.0)

	# 使用 Tween 让英雄快速移动到目标位置
	var tween: Tween = hero.create_tween()
	tween.tween_property(hero, "global_position", end_pos, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# 对路径上的敌人造成伤害和减速
	for enemy: Node2D in enemies_on_path:
		if not is_instance_valid(enemy):
			continue
		_deal_skill_damage(enemy, rush_damage)
		_apply_slow(enemy, 0.3, 2.0)


## 狼嚎战吼：AOE 恐惧 + 护盾
func _execute_wolf_howl() -> void:
	if hero == null or _stats == null:
		return

	var howl_radius: float = 64.0
	var hero_pos: Vector2 = hero.global_position

	# 获取范围内的所有敌人
	var enemies: Array = _get_enemies_in_radius(hero_pos, howl_radius)

	# 对所有敌人施加恐惧 2 秒
	for enemy: Node2D in enemies:
		if not is_instance_valid(enemy):
			continue
		_apply_fear(enemy, 2.0)

	# 英雄获得护盾（额外 30 HP）
	_stats.add_modifier("hp", "wolf_howl_shield", 30.0)
	_stats.current_hp = minf(_stats.current_hp + 30.0, _stats.max_hp)
	_stats.health_changed.emit(_stats.current_hp, _stats.max_hp)

	# 5 秒后移除护盾
	if hero.is_inside_tree():
		hero.get_tree().create_timer(5.0).timeout.connect(
			func() -> void:
				if _stats and is_instance_valid(hero):
					_stats.remove_modifier("hp", "wolf_howl_shield")
		)


## 白狼化身：变身 8 秒，攻击范围 x1.5，攻速 +50%
func _execute_wolf_form() -> void:
	if hero == null or _stats == null:
		return

	var duration: float = float(ultimate_data.get("duration", 8.0))
	var range_bonus: float = float(ultimate_data.get("attack_range_bonus", 1.5))
	var speed_bonus: float = float(ultimate_data.get("attack_speed_bonus", 0.5))

	# 攻击范围加成（乘法 -> 加上额外部分）
	var base_range: float = _stats.get_stat("attack_range")
	var extra_range: float = base_range * (range_bonus - 1.0)
	_stats.add_modifier("attack_range", "wolf_form_range", extra_range)

	# 攻速加成
	var base_attack_speed: float = _stats.get_stat("attack_speed")
	var extra_speed: float = base_attack_speed * speed_bonus
	_stats.add_modifier("attack_speed", "wolf_form_speed", extra_speed)

	# duration 秒后移除所有变身加成
	if hero.is_inside_tree():
		hero.get_tree().create_timer(duration).timeout.connect(
			func() -> void:
				if _stats and is_instance_valid(hero):
					_stats.remove_modifier("attack_range", "wolf_form_range")
					_stats.remove_modifier("attack_speed", "wolf_form_speed")
		)

# ============================================================
# 流星法师 -- 技能实现
# ============================================================

## 流星雨：区域持续伤害 3 秒，每 0.5 秒 tick，减速 30%
func _execute_meteor_shower() -> void:
	if hero == null or _stats == null:
		return
	if not hero.is_inside_tree():
		return

	var spell_power: float = _stats.get_stat("spell_power")
	var tick_damage: float = spell_power * 0.5
	var duration: float = 3.0
	var tick_interval: float = 0.5
	var radius: float = 64.0

	# 以最近敌人位置为中心（如果没有则以英雄前方为中心）
	var center: Vector2 = hero.global_position + Vector2(60, 0)
	var nearest: Node2D = _get_nearest_enemy()
	if nearest:
		center = nearest.global_position

	# 使用定时器实现持续 tick 伤害
	var ticks_total: int = int(duration / tick_interval)
	var tick_count: int = 0

	var tick_timer: Timer = Timer.new()
	tick_timer.wait_time = tick_interval
	tick_timer.one_shot = false
	hero.add_child(tick_timer)
	tick_timer.start()

	tick_timer.timeout.connect(
		func() -> void:
			tick_count += 1
			# 对范围内的敌人造成伤害和减速
			var enemies: Array = _get_enemies_in_radius(center, radius)
			for enemy: Node2D in enemies:
				if not is_instance_valid(enemy):
					continue
				_deal_skill_damage(enemy, tick_damage)
				_apply_slow(enemy, 0.3, tick_interval + 0.1)

			if tick_count >= ticks_total:
				tick_timer.stop()
				tick_timer.queue_free()
	)


## 彗星撞击：直线高伤 + 击退
func _execute_comet_strike() -> void:
	if hero == null or _stats == null:
		return

	var atk: float = _stats.get_stat("attack")
	var strike_damage: float = atk * 3.5
	var knockback_force: float = 100.0

	# 面朝方向
	var direction: Vector2 = Vector2.RIGHT
	if hero.get("facing_right") != null:
		direction = Vector2.RIGHT if hero.facing_right else Vector2.LEFT
	elif hero.get("move_direction") != null and hero.move_direction != Vector2.ZERO:
		direction = hero.move_direction.normalized()

	var start_pos: Vector2 = hero.global_position
	var projectile_range: float = 120.0

	# 在直线路径上检测敌人
	var enemies_on_line: Array = _get_enemies_on_path(start_pos, start_pos + direction * projectile_range, 16.0)

	for enemy: Node2D in enemies_on_line:
		if not is_instance_valid(enemy):
			continue
		_deal_skill_damage(enemy, strike_damage)
		_apply_knockback(enemy, direction, knockback_force)


## 天陨：巨型 AOE，spell_power * 10
func _execute_celestial_fall() -> void:
	if hero == null or _stats == null:
		return

	var spell_power: float = _stats.get_stat("spell_power")
	var fall_damage: float = spell_power * 10.0
	var radius: float = float(ultimate_data.get("radius", 128))

	# 以英雄为中心
	var center: Vector2 = hero.global_position

	var enemies: Array = _get_enemies_in_radius(center, radius)
	for enemy: Node2D in enemies:
		if not is_instance_valid(enemy):
			continue
		_deal_skill_damage(enemy, fall_damage)

# ============================================================
# 效果应用
# ============================================================

## 对目标造成技能伤害
func _deal_skill_damage(target: Node2D, raw_damage: float) -> void:
	if not is_instance_valid(target):
		return

	var target_stats: StatsComponent = null
	if target.has_node("StatsComponent"):
		target_stats = target.get_node("StatsComponent")
	if target_stats == null:
		return

	# 伤害公式：max(raw_damage - defense, 1)
	var defense: float = target_stats.get_stat("defense")
	var final_damage: int = maxi(int(raw_damage - defense), 1)
	target_stats.take_damage(float(final_damage))

	# 记录伤害
	var gm: Node = _get_game_manager()
	if gm and gm.has_method("record_damage"):
		gm.record_damage(float(final_damage))

	# 检查击杀
	if not target_stats.is_alive():
		if gm and gm.has_method("record_kill"):
			gm.record_kill()

	# 飘字：尝试使用 DamageSystem
	var damage_system: Node = null
	if hero.is_inside_tree():
		damage_system = hero.get_tree().root.get_node_or_null("DamageSystem")
	if damage_system and damage_system.has_method("create_damage_number"):
		damage_system.create_damage_number(target.global_position, final_damage, false)


## 对目标施加减速效果
func _apply_slow(target: Node2D, slow_percent: float, duration: float) -> void:
	if not is_instance_valid(target):
		return
	if not target.has_node("StatsComponent"):
		return

	var target_stats: StatsComponent = target.get_node("StatsComponent")
	var current_speed: float = target_stats.get_stat("speed")
	var slow_amount: float = -current_speed * slow_percent
	var source_id: String = "skill_slow_%d" % target.get_instance_id()

	target_stats.add_modifier("speed", source_id, slow_amount)

	# duration 后移除减速
	if hero.is_inside_tree():
		hero.get_tree().create_timer(duration).timeout.connect(
			func() -> void:
				if is_instance_valid(target) and target.has_node("StatsComponent"):
					var ts: StatsComponent = target.get_node("StatsComponent")
					ts.remove_modifier("speed", source_id)
		)


## 对目标施加恐惧效果（2 秒反向移动）
func _apply_fear(target: Node2D, duration: float) -> void:
	if not is_instance_valid(target):
		return

	# 在 EnemyBase 中设置 is_feared 标志
	if target.has_method("set") and "is_feared" in target:
		target.is_feared = true
	else:
		# 如果目标没有 is_feared 属性，用 meta 标记
		target.set_meta("is_feared", true)

	# duration 后解除恐惧
	if hero.is_inside_tree():
		hero.get_tree().create_timer(duration).timeout.connect(
			func() -> void:
				if is_instance_valid(target):
					if "is_feared" in target:
						target.is_feared = false
					else:
						target.set_meta("is_feared", false)
		)


## 对目标施加击退效果
func _apply_knockback(target: Node2D, direction: Vector2, force: float) -> void:
	if not is_instance_valid(target):
		return

	var knockback_offset: Vector2 = direction.normalized() * force
	var target_pos: Vector2 = target.global_position

	# 使用 Tween 实现平滑击退
	var tween: Tween = target.create_tween()
	tween.tween_property(target, "global_position", target_pos + knockback_offset, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

# ============================================================
# 终极技蓄力信号连接
# ============================================================

## 连接 GameManager 的统计信号
func _connect_charge_signals() -> void:
	if hero == null or not hero.is_inside_tree():
		# 延迟到 ready 时再连接
		if hero:
			hero.ready.connect(_connect_charge_signals, CONNECT_ONE_SHOT)
		return

	var gm: Node = _get_game_manager()
	if gm == null:
		return

	match ultimate_charge_type:
		"kill_count":
			if gm.has_signal("kill_recorded"):
				if not gm.kill_recorded.is_connected(_on_kill_recorded):
					gm.kill_recorded.connect(_on_kill_recorded)
		"damage_dealt":
			# GameManager 没有 damage_recorded 信号，用 _process 轮询
			# 或在 _deal_skill_damage 中主动调用 add_ultimate_charge
			pass


## 击杀回调：每次击杀增加 1 点蓄力
func _on_kill_recorded(_total_kills: int) -> void:
	if ultimate_charge_type == "kill_count":
		add_ultimate_charge(1.0)

# ============================================================
# 工具方法
# ============================================================

## 获取 GameManager 引用
func _get_game_manager() -> Node:
	if hero and hero.is_inside_tree():
		return hero.get_tree().root.get_node_or_null("GameManager")
	return null


## 获取最近的敌人（遍历场景树中 "enemies" 组）
func _get_nearest_enemy() -> Node2D:
	if hero == null or not hero.is_inside_tree():
		return null

	var nearest: Node2D = null
	var nearest_dist: float = INF

	var enemies: Array[Node] = hero.get_tree().get_nodes_in_group("enemies")
	for node: Node in enemies:
		if node is Node2D and is_instance_valid(node):
			var enemy: Node2D = node as Node2D
			if enemy.has_node("StatsComponent"):
				var enemy_stats: StatsComponent = enemy.get_node("StatsComponent")
				if not enemy_stats.is_alive():
					continue
			var dist: float = hero.global_position.distance_squared_to(enemy.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = enemy

	return nearest


## 获取圆形范围内的敌人
func _get_enemies_in_radius(center: Vector2, radius: float) -> Array:
	var result: Array = []
	if hero == null or not hero.is_inside_tree():
		return result

	var enemies: Array[Node] = hero.get_tree().get_nodes_in_group("enemies")
	for node: Node in enemies:
		if node is Node2D and is_instance_valid(node):
			var enemy: Node2D = node as Node2D
			if enemy.has_node("StatsComponent"):
				var enemy_stats: StatsComponent = enemy.get_node("StatsComponent")
				if not enemy_stats.is_alive():
					continue
			var dist: float = center.distance_to(enemy.global_position)
			if dist <= radius:
				result.append(enemy)

	return result


## 获取路径上的敌人（以 start->end 为中心线，half_width 为半宽）
func _get_enemies_on_path(start: Vector2, end: Vector2, half_width: float) -> Array:
	var result: Array = []
	if hero == null or not hero.is_inside_tree():
		return result

	var path_dir: Vector2 = (end - start).normalized()
	var path_length: float = start.distance_to(end)
	var path_normal: Vector2 = Vector2(-path_dir.y, path_dir.x)

	var enemies: Array[Node] = hero.get_tree().get_nodes_in_group("enemies")
	for node: Node in enemies:
		if node is Node2D and is_instance_valid(node):
			var enemy: Node2D = node as Node2D
			if enemy.has_node("StatsComponent"):
				var enemy_stats: StatsComponent = enemy.get_node("StatsComponent")
				if not enemy_stats.is_alive():
					continue

			var to_enemy: Vector2 = enemy.global_position - start
			var proj_along: float = to_enemy.dot(path_dir)
			var proj_perp: float = absf(to_enemy.dot(path_normal))

			# 在路径长度范围内且垂直距离在半宽内
			if proj_along >= 0.0 and proj_along <= path_length and proj_perp <= half_width:
				result.append(enemy)

	return result
