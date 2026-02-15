class_name WolfHowlSkill
extends SkillResource
## 狼嚎战吼：AOE 恐惧 + 护盾

func _init() -> void:
	skill_id = "wolf_howl"
	skill_type = "active"
	cooldown = 15.0


func execute(caster: Node2D, stats: StatsComponent, skill_system: Node) -> void:
	if caster == null or stats == null:
		return

	var howl_radius: float = 64.0
	howl_radius *= CardEffects.get_skill_range_multiplier(skill_system)
	var hero_pos: Vector2 = caster.global_position

	# 获取范围内的所有敌人
	var enemies: Array = skill_system._get_enemies_in_radius(hero_pos, howl_radius)

	# 恐惧 2 秒
	for enemy: Node2D in enemies:
		if not is_instance_valid(enemy):
			continue
		skill_system._apply_fear(enemy, 2.0)

	# 英雄获得护盾（额外 30 HP）
	stats.add_modifier("hp", "wolf_howl_shield", 30.0)
	stats.current_hp = minf(stats.current_hp + 30.0, stats.max_hp)
	stats.health_changed.emit(stats.current_hp, stats.max_hp)

	# 5 秒后移除护盾
	if caster.is_inside_tree():
		caster.get_tree().create_timer(5.0).timeout.connect(
			func() -> void:
				if stats and is_instance_valid(caster):
					stats.remove_modifier("hp", "wolf_howl_shield")
		)


func get_description() -> String:
	return "AOE恐惧2秒+自身护盾"
