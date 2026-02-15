class_name GravityWellSkill
extends SkillResource
## 重力井：目标位置生成黑洞，吸引敌人3秒

func _init() -> void:
	skill_id = "gravity_well"
	skill_type = "active"
	cooldown = 12.0


func execute(caster: Node2D, stats: StatsComponent, skill_system: Node) -> void:
	if caster == null or stats == null:
		return
	if not caster.is_inside_tree():
		return

	var spell_power: float = stats.get_stat("spell_power")
	var tick_damage: float = spell_power * 0.3
	var duration: float = 3.0
	var tick_interval: float = 0.25
	var well_radius: float = 64.0
	var pull_force: float = 15.0

	well_radius *= CardEffects.get_skill_range_multiplier(skill_system)

	# 放置在最近敌人的位置
	var center: Vector2 = caster.global_position + Vector2(40, 0)
	var nearest: Node2D = skill_system._get_nearest_enemy()
	if nearest:
		center = nearest.global_position

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
			var enemies: Array = skill_system._get_enemies_in_radius(center, well_radius)
			for enemy: Node2D in enemies:
				if not is_instance_valid(enemy):
					continue
				# 拉拽向中心
				var pull_dir: Vector2 = (center - enemy.global_position).normalized()
				var dist: float = enemy.global_position.distance_to(center)
				if dist > 5.0:
					enemy.global_position += pull_dir * minf(pull_force, dist)
				# 每 tick 造成少量伤害
				skill_system._deal_skill_damage(enemy, tick_damage)

				# 终极技蓄力（拉拽型）
				if skill_system.ultimate_charge_type == "pull_count":
					skill_system.add_ultimate_charge(1.0)

			if tick_count >= ticks_total:
				tick_timer.stop()
				tick_timer.queue_free()
	)


func get_description() -> String:
	return "目标位置生成黑洞，吸引敌人3秒"
