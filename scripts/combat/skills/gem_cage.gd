class_name GemCageSkill
extends SkillResource
## 宝石牢笼：区域结界困住敌人3秒

func _init() -> void:
	skill_id = "gem_cage"
	skill_type = "active"
	cooldown = 15.0


func execute(caster: Node2D, stats: StatsComponent, skill_system: Node) -> void:
	if caster == null or stats == null:
		return
	if not caster.is_inside_tree():
		return

	var cage_radius: float = 48.0
	var cage_duration: float = 3.0

	cage_radius *= CardEffects.get_skill_range_multiplier(skill_system)

	# 放置在最近敌人的位置
	var center: Vector2 = caster.global_position + Vector2(60, 0)
	var nearest: Node2D = skill_system._get_nearest_enemy()
	if nearest:
		center = nearest.global_position

	# 对范围内所有敌人施加定身（100% 减速 = 冻结移动）
	var enemies: Array = skill_system._get_enemies_in_radius(center, cage_radius)
	for enemy: Node2D in enemies:
		if not is_instance_valid(enemy):
			continue
		skill_system._apply_slow(enemy, 1.0, cage_duration)

		# 终极技蓄力（技能命中型）
		if skill_system.ultimate_charge_type == "skill_hit":
			skill_system.add_ultimate_charge(1.0)


func get_description() -> String:
	return "区域结界，困住敌人3秒"
