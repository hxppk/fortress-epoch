class_name MeteorShowerSkill
extends SkillResource
## 流星雨：区域持续伤害 3 秒，每 0.5 秒 tick，减速 30%

func _init() -> void:
	skill_id = "meteor_shower"
	skill_type = "active"
	cooldown = 12.0


func execute(caster: Node2D, stats: StatsComponent, skill_system: Node) -> void:
	if caster == null or stats == null:
		return
	if not caster.is_inside_tree():
		return

	var spell_power: float = stats.get_stat("spell_power")
	var tick_damage: float = spell_power * 0.5
	var duration: float = 3.0
	var tick_interval: float = 0.5
	var radius: float = 64.0
	var slow_percent: float = 0.3

	# 应用卡牌特定技能修改
	var specific_mods: Array = CardEffects.get_specific_skill_modifiers(skill_system, "meteor_shower")
	for mod: Dictionary in specific_mods:
		if mod.has("duration_bonus"):
			duration += float(mod["duration_bonus"])
		if mod.has("slow_bonus"):
			slow_percent += float(mod["slow_bonus"])

	# 应用卡牌全局范围倍率
	var range_mult: float = CardEffects.get_skill_range_multiplier(skill_system)
	radius *= range_mult

	# 以最近敌人位置为中心
	var center: Vector2 = caster.global_position + Vector2(60, 0)
	var nearest: Node2D = skill_system._get_nearest_enemy()
	if nearest:
		center = nearest.global_position

	# 持续 tick 伤害
	var ticks_total: int = int(duration / tick_interval)
	var tick_count: int = 0

	var tick_timer: Timer = Timer.new()
	tick_timer.wait_time = tick_interval
	tick_timer.one_shot = false
	caster.add_child(tick_timer)
	tick_timer.start()

	tick_timer.timeout.connect(
		func() -> void:
			tick_count += 1
			var enemies: Array = skill_system._get_enemies_in_radius(center, radius)
			for enemy: Node2D in enemies:
				if not is_instance_valid(enemy):
					continue
				skill_system._deal_skill_damage(enemy, tick_damage)
				skill_system._apply_slow(enemy, slow_percent, tick_interval + 0.1)

			if tick_count >= ticks_total:
				tick_timer.stop()
				tick_timer.queue_free()
	)


func get_description() -> String:
	return "区域持续3秒+减速30%"
