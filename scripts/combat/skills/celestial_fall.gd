class_name CelestialFallSkill
extends SkillResource
## 天陨：巨型 AOE，spell_power * 10

func _init() -> void:
	skill_id = "celestial_fall"
	skill_type = "ultimate"
	charge_type = "damage_dealt"
	charge_max = 1800.0


func execute(caster: Node2D, stats: StatsComponent, skill_system: Node) -> void:
	if caster == null or stats == null:
		return

	var spell_power: float = stats.get_stat("spell_power")
	var fall_damage: float = spell_power * 10.0
	var radius: float = 128.0

	# 从 ultimate_data 读取配置
	if skill_system and "ultimate_data" in skill_system:
		var ud: Dictionary = skill_system.ultimate_data
		radius = float(ud.get("radius", 128))

	radius *= CardEffects.get_skill_range_multiplier(skill_system)

	var center: Vector2 = caster.global_position

	var enemies: Array = skill_system._get_enemies_in_radius(center, radius)
	for enemy: Node2D in enemies:
		if not is_instance_valid(enemy):
			continue
		skill_system._deal_skill_damage(enemy, fall_damage)


func get_description() -> String:
	return "巨型陨石，大范围毁灭性打击"
