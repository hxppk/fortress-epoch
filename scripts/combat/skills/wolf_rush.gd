class_name WolfRushSkill
extends SkillResource
## 奔狼突袭：短距冲刺 + 路径伤害 + 减速

func _init() -> void:
	skill_id = "wolf_rush"
	skill_type = "active"
	cooldown = 10.0


func execute(caster: Node2D, stats: StatsComponent, skill_system: Node) -> void:
	if caster == null or stats == null:
		return

	var atk: float = stats.get_stat("attack")
	var rush_damage: float = atk * 2.0
	var rush_distance: float = 80.0
	var slow_duration: float = 2.0

	# 应用卡牌特定技能修改
	var specific_mods: Array = CardEffects.get_specific_skill_modifiers(skill_system, "wolf_rush")
	for mod: Dictionary in specific_mods:
		if mod.has("damage_bonus"):
			rush_damage *= (1.0 + float(mod["damage_bonus"]))
		if mod.has("slow_duration_bonus"):
			slow_duration += float(mod["slow_duration_bonus"])

	# 应用卡牌全局范围倍率
	var range_mult: float = CardEffects.get_skill_range_multiplier(skill_system)
	rush_distance *= range_mult

	# 计算冲刺方向（面朝方向）
	var direction: Vector2 = Vector2.RIGHT
	if "facing_right" in caster:
		direction = Vector2.RIGHT if caster.facing_right else Vector2.LEFT
	if "move_direction" in caster and caster.move_direction != Vector2.ZERO:
		direction = caster.move_direction.normalized()

	var start_pos: Vector2 = caster.global_position
	var end_pos: Vector2 = start_pos + direction * rush_distance

	# 路径上的敌人
	var enemies_on_path: Array = skill_system._get_enemies_on_path(start_pos, end_pos, 24.0)

	# Tween 冲刺移动
	var tween: Tween = caster.create_tween()
	tween.tween_property(caster, "global_position", end_pos, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# 对路径上的敌人造成伤害和减速
	for enemy: Node2D in enemies_on_path:
		if not is_instance_valid(enemy):
			continue
		skill_system._deal_skill_damage(enemy, rush_damage)
		skill_system._apply_slow(enemy, 0.3, slow_duration)


func get_description() -> String:
	return "短距离冲刺，路径伤害+减速"
