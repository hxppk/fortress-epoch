class_name CometStrikeSkill
extends SkillResource
## 彗星撞击：直线高伤害 + 击退

func _init() -> void:
	skill_id = "comet_strike"
	skill_type = "active"
	cooldown = 14.0


func execute(caster: Node2D, stats: StatsComponent, skill_system: Node) -> void:
	if caster == null or stats == null:
		return

	var atk: float = stats.get_stat("attack")
	var strike_damage: float = atk * 3.5
	var knockback_force: float = 100.0

	# 面朝方向
	var direction: Vector2 = Vector2.RIGHT
	if "facing_right" in caster:
		direction = Vector2.RIGHT if caster.facing_right else Vector2.LEFT
	if "move_direction" in caster and caster.move_direction != Vector2.ZERO:
		direction = caster.move_direction.normalized()

	var start_pos: Vector2 = caster.global_position
	var projectile_range: float = 120.0
	projectile_range *= CardEffects.get_skill_range_multiplier(skill_system)

	# 在直线路径上检测敌人
	var enemies_on_line: Array = skill_system._get_enemies_on_path(start_pos, start_pos + direction * projectile_range, 16.0)

	for enemy: Node2D in enemies_on_line:
		if not is_instance_valid(enemy):
			continue
		skill_system._deal_skill_damage(enemy, strike_damage)
		skill_system._apply_knockback(enemy, direction, knockback_force)


func get_description() -> String:
	return "直线高伤害+击退"
