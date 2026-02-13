extends Node
## DamageSystem — 伤害计算 + 飘字（Autoload 单例）
## 公式：damage = max(ATK - DEF, 1)，暴击 x2

# ============================================================
# 伤害计算
# ============================================================

## 计算伤害，返回 { "damage": int, "is_crit": bool }
func calculate_damage(attacker: StatsComponent, defender: StatsComponent) -> Dictionary:
	var atk: float = attacker.get_stat("attack")
	var def: float = defender.get_stat("defense")
	var crit_rate: float = attacker.get_stat("crit_rate")  # 0.0 ~ 1.0

	var base_damage: int = maxi(int(atk - def), 1)

	var is_crit: bool = randf() < crit_rate
	if is_crit:
		base_damage *= 2

	return { "damage": base_damage, "is_crit": is_crit }

# ============================================================
# 伤害应用
# ============================================================

## 对目标造成伤害并触发视觉反馈
func apply_damage(attacker: Node2D, defender: Node2D, damage_info: Dictionary) -> void:
	# 找到 defender 身上的 StatsComponent
	var defender_stats: StatsComponent = _find_stats_component(defender)
	if defender_stats == null:
		return

	var actual_damage: float = defender_stats.take_damage(float(damage_info["damage"]))

	# 记录伤害到 GameManager
	if GameManager.has_method("record_damage"):
		GameManager.record_damage(actual_damage)

	# 击杀统计由 EnemyBase.die() 负责，此处不再重复调用

	# 飘字
	create_damage_number(defender.global_position, damage_info["damage"], damage_info["is_crit"])

	# 播放击中音效
	if CombatFeedback and CombatFeedback.has_method("play_hit_sound"):
		CombatFeedback.play_hit_sound()

	# 闪白 & 缩放反馈
	if CombatFeedback:
		# 被击者闪白
		var defender_sprite: Node2D = _find_sprite(defender)
		if defender_sprite and CombatFeedback.has_method("flash_white"):
			CombatFeedback.flash_white(defender_sprite)

		# 攻击者缩放弹性效果
		var attacker_sprite: Node2D = _find_sprite(attacker)
		if attacker_sprite and CombatFeedback.has_method("hit_scale_effect"):
			CombatFeedback.hit_scale_effect(attacker_sprite)

# ============================================================
# 飘字
# ============================================================

## 在指定位置创建飘字
func create_damage_number(position: Vector2, amount: int, is_crit: bool) -> void:
	var label := Label.new()
	label.text = str(amount)
	label.z_index = 100
	label.position = position + Vector2(randf_range(-8, 8), -16)  # 略微随机偏移

	# 外观
	if is_crit:
		label.add_theme_font_size_override("font_size", 28)
		label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color.WHITE)

	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)

	# 添加到场景树
	var tree := get_tree()
	if tree and tree.current_scene:
		tree.current_scene.add_child(label)
	else:
		add_child(label)

	# Tween 动画：向上飘 30px + 淡出，0.8 秒后销毁
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 30.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.chain().tween_callback(label.queue_free)

# ============================================================
# 内部工具
# ============================================================

## 在节点或其子节点中查找 StatsComponent
func _find_stats_component(node: Node) -> StatsComponent:
	if node is StatsComponent:
		return node as StatsComponent
	for child in node.get_children():
		if child is StatsComponent:
			return child as StatsComponent
	return null


## 在节点或其子节点中查找可显示的 Sprite（Sprite2D / AnimatedSprite2D）
func _find_sprite(node: Node) -> Node2D:
	if node is Sprite2D or node is AnimatedSprite2D:
		return node as Node2D
	for child in node.get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			return child as Node2D
	return null
