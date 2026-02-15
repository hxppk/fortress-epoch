class_name PrismRefractSkill
extends SkillResource
## 棱光折射：光线弹射6次，敌人越密伤害越高

func _init() -> void:
	skill_id = "prism_refract"
	skill_type = "active"
	cooldown = 10.0


func execute(caster: Node2D, stats: StatsComponent, skill_system: Node) -> void:
	if caster == null or stats == null:
		return

	var spell_power: float = stats.get_stat("spell_power")
	var bounce_damage: float = spell_power * 1.2
	var max_bounces: int = 6
	var bounce_range: float = 100.0

	bounce_range *= CardEffects.get_skill_range_multiplier(skill_system)

	# 从最近敌人开始弹射
	var first_target: Node2D = skill_system._get_nearest_enemy()
	if first_target == null:
		return

	var already_hit: Array[Node2D] = []
	var current_target: Node2D = first_target
	var damage_mult: float = 1.0

	for bounce: int in range(max_bounces):
		if current_target == null or not is_instance_valid(current_target):
			break

		# 每次弹射伤害递增 10%
		var this_damage: float = bounce_damage * damage_mult
		skill_system._deal_skill_damage(current_target, this_damage)
		already_hit.append(current_target)
		damage_mult += 0.1

		# 终极技蓄力（技能命中型）
		if skill_system.ultimate_charge_type == "skill_hit":
			skill_system.add_ultimate_charge(1.0)

		# 找下一个弹射目标（范围内最近的未命中敌人）
		var next_target: Node2D = _find_bounce_target(
			current_target.global_position, bounce_range, already_hit, skill_system
		)
		# 如果没有新目标，可以重复弹射已命中的
		if next_target == null:
			next_target = _find_bounce_target(
				current_target.global_position, bounce_range, [], skill_system
			)
		current_target = next_target


func _find_bounce_target(from_pos: Vector2, max_range: float, exclude: Array, skill_system: Node) -> Node2D:
	var candidates: Array = skill_system._get_enemies_in_radius(from_pos, max_range)
	var nearest: Node2D = null
	var nearest_dist: float = INF

	for enemy: Node2D in candidates:
		if not is_instance_valid(enemy):
			continue
		if exclude.has(enemy):
			continue
		var dist: float = from_pos.distance_squared_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	return nearest


func get_description() -> String:
	return "光线弹射6次，敌人越密伤害越高"
