class_name RainbowPrismSkill
extends SkillResource
## 七彩虹光：扇形持续光线5秒；蓄力：技能命中30次

func _init() -> void:
	skill_id = "rainbow_prism"
	skill_type = "ultimate"
	charge_type = "skill_hit"
	charge_max = 30.0


func execute(caster: Node2D, stats: StatsComponent, skill_system: Node) -> void:
	if caster == null or stats == null:
		return
	if not caster.is_inside_tree():
		return

	var spell_power: float = stats.get_stat("spell_power")
	var tick_damage: float = spell_power * 0.8
	var duration: float = 5.0
	var tick_interval: float = 0.3
	var fan_radius: float = 140.0
	var fan_angle_deg: float = 90.0

	fan_radius *= CardEffects.get_skill_range_multiplier(skill_system)

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
			if not is_instance_valid(caster) or not stats.is_alive():
				tick_timer.stop()
				tick_timer.queue_free()
				return

			var center: Vector2 = caster.global_position
			# 面朝方向
			var direction: Vector2 = Vector2.RIGHT
			if "facing_right" in caster:
				direction = Vector2.RIGHT if caster.facing_right else Vector2.LEFT

			# 扇形范围检测
			var half_angle_rad: float = deg_to_rad(fan_angle_deg / 2.0)
			var enemies: Array = skill_system._get_enemies_in_radius(center, fan_radius)
			for enemy: Node2D in enemies:
				if not is_instance_valid(enemy):
					continue
				var to_enemy: Vector2 = (enemy.global_position - center).normalized()
				var angle_to: float = direction.angle_to(to_enemy)
				if absf(angle_to) <= half_angle_rad:
					skill_system._deal_skill_damage(enemy, tick_damage)

			if tick_count >= ticks_total:
				tick_timer.stop()
				tick_timer.queue_free()
	)


func get_description() -> String:
	return "扇形持续光线5秒"
