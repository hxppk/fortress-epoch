class_name SingularityCollapseSkill
extends SkillResource
## 奇点崩塌：超大引力场拉拽全屏敌人到中心后爆炸；蓄力：拉拽100敌人

func _init() -> void:
	skill_id = "singularity_collapse"
	skill_type = "ultimate"
	charge_type = "pull_count"
	charge_max = 100.0


func execute(caster: Node2D, stats: StatsComponent, skill_system: Node) -> void:
	if caster == null or stats == null:
		return
	if not caster.is_inside_tree():
		return

	var spell_power: float = stats.get_stat("spell_power")
	var collapse_damage: float = spell_power * 12.0
	var pull_radius: float = 200.0
	var pull_duration: float = 2.0
	var pull_interval: float = 0.15
	var pull_force: float = 25.0

	pull_radius *= CardEffects.get_skill_range_multiplier(skill_system)

	var center: Vector2 = caster.global_position
	var pull_ticks: int = int(pull_duration / pull_interval)
	var tick_count: int = 0

	# 阶段1：持续拉拽所有敌人到中心
	var tick_timer: Timer = Timer.new()
	tick_timer.wait_time = pull_interval
	tick_timer.one_shot = false
	caster.add_child(tick_timer)
	tick_timer.start()

	tick_timer.timeout.connect(
		func() -> void:
			tick_count += 1
			var enemies: Array = skill_system._get_enemies_in_radius(center, pull_radius)
			for enemy: Node2D in enemies:
				if not is_instance_valid(enemy):
					continue
				var pull_dir: Vector2 = (center - enemy.global_position).normalized()
				var dist: float = enemy.global_position.distance_to(center)
				if dist > 8.0:
					enemy.global_position += pull_dir * minf(pull_force, dist)

			if tick_count >= pull_ticks:
				tick_timer.stop()
				tick_timer.queue_free()

				# 阶段2：爆炸伤害
				var blast_enemies: Array = skill_system._get_enemies_in_radius(center, pull_radius * 0.6)
				for enemy: Node2D in blast_enemies:
					if not is_instance_valid(enemy):
						continue
					skill_system._deal_skill_damage(enemy, collapse_damage)

				# 击退效果（爆炸后向外推散）
				for enemy: Node2D in blast_enemies:
					if not is_instance_valid(enemy):
						continue
					var push_dir: Vector2 = (enemy.global_position - center).normalized()
					if push_dir.length_squared() < 0.01:
						push_dir = Vector2.RIGHT
					skill_system._apply_knockback(enemy, push_dir, 60.0)
	)


func get_description() -> String:
	return "超大引力场，拉全屏敌人到中心后爆炸"
