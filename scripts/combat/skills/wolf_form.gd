class_name WolfFormSkill
extends SkillResource
## 白狼化身：变身 8 秒，攻击范围 x1.5，攻速 +50%

func _init() -> void:
	skill_id = "wolf_form"
	skill_type = "ultimate"
	charge_type = "kill_count"
	charge_max = 35.0


func execute(caster: Node2D, stats: StatsComponent, skill_system: Node) -> void:
	if caster == null or stats == null:
		return

	var duration: float = 8.0
	var range_bonus: float = 1.5
	var speed_bonus: float = 0.5

	# 从 ultimate_data 读取配置（如果有的话）
	if skill_system and "ultimate_data" in skill_system:
		var ud: Dictionary = skill_system.ultimate_data
		duration = float(ud.get("duration", 8.0))
		range_bonus = float(ud.get("attack_range_bonus", 1.5))
		speed_bonus = float(ud.get("attack_speed_bonus", 0.5))

	# 攻击范围加成
	var base_range: float = stats.get_stat("attack_range")
	var extra_range: float = base_range * (range_bonus - 1.0)
	stats.add_modifier("attack_range", "wolf_form_range", extra_range)

	# 攻速加成
	var base_attack_speed: float = stats.get_stat("attack_speed")
	var extra_speed: float = base_attack_speed * speed_bonus
	stats.add_modifier("attack_speed", "wolf_form_speed", extra_speed)

	# duration 秒后移除
	if caster.is_inside_tree():
		caster.get_tree().create_timer(duration).timeout.connect(
			func() -> void:
				if stats and is_instance_valid(caster):
					stats.remove_modifier("attack_range", "wolf_form_range")
					stats.remove_modifier("attack_speed", "wolf_form_speed")
		)


func get_description() -> String:
	return "变身8秒，攻击范围和攻速大幅提升"
