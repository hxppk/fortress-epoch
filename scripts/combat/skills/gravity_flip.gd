class_name GravityFlipSkill
extends SkillResource
## 引力翻转：将周围敌人抛向空中2秒后砸落AOE

func _init() -> void:
	skill_id = "gravity_flip"
	skill_type = "active"
	cooldown = 15.0


func execute(caster: Node2D, stats: StatsComponent, skill_system: Node) -> void:
	if caster == null or stats == null:
		return
	if not caster.is_inside_tree():
		return

	var spell_power: float = stats.get_stat("spell_power")
	var flip_radius: float = 56.0
	var slam_damage: float = spell_power * 3.0
	var float_duration: float = 2.0

	flip_radius *= CardEffects.get_skill_range_multiplier(skill_system)

	var center: Vector2 = caster.global_position
	var enemies: Array = skill_system._get_enemies_in_radius(center, flip_radius)

	# 第一阶段：将敌人"抛起"（100% 减速 + 视觉上移）
	for enemy: Node2D in enemies:
		if not is_instance_valid(enemy):
			continue
		skill_system._apply_slow(enemy, 1.0, float_duration)

		# 视觉偏移（模拟浮空）
		if enemy.has_node("Sprite2D"):
			var spr: Sprite2D = enemy.get_node("Sprite2D") as Sprite2D
			if spr:
				var tween_up: Tween = enemy.create_tween()
				tween_up.tween_property(spr, "position:y", -20.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

		# 终极技蓄力（拉拽型）
		if skill_system.ultimate_charge_type == "pull_count":
			skill_system.add_ultimate_charge(1.0)

	# 第二阶段：2 秒后砸落 AOE 伤害
	if caster.is_inside_tree():
		caster.get_tree().create_timer(float_duration).timeout.connect(
			func() -> void:
				# 砸落伤害
				var slam_enemies: Array = skill_system._get_enemies_in_radius(center, flip_radius)
				for enemy: Node2D in slam_enemies:
					if not is_instance_valid(enemy):
						continue
					skill_system._deal_skill_damage(enemy, slam_damage)

					# 恢复精灵位置
					if enemy.has_node("Sprite2D"):
						var spr: Sprite2D = enemy.get_node("Sprite2D") as Sprite2D
						if spr:
							var tween_down: Tween = enemy.create_tween()
							tween_down.tween_property(spr, "position:y", 0.0, 0.15).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		)


func get_description() -> String:
	return "将周围敌人抛向空中2秒后砸落AOE"
