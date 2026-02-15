class_name SkillSystem
extends Node
## SkillSystem -- 管理英雄主动技能 CD + 终极技蓄力
## 从 heroes.json 技能数据初始化，通过 SkillResource 脚本调度技能执行。

# ============================================================
# 信号
# ============================================================

signal skill_used(skill_id: String)
signal skill_ready(skill_id: String)
signal ultimate_charged()
signal ultimate_used()
signal cooldown_updated(slot: int, remaining: float, total: float)

# ============================================================
# 属性
# ============================================================

## 所有者英雄节点
var hero: Node2D = null

## 技能槽 { skill_id: { "data": Dictionary, "resource": SkillResource, "cooldown_remaining": float, "cooldown_total": float, "is_ready": bool, "slot": int } }
var skills: Dictionary = {}

## 终极技蓄力进度
var ultimate_charge: float = 0.0

## 终极技满蓄力值
var ultimate_max_charge: float = 50.0

## 终极技蓄力类型："kill_count" | "damage_dealt" | "skill_hit" | "pull_count"
var ultimate_charge_type: String = "kill_count"

## 终极技数据
var ultimate_data: Dictionary = {}

## 终极技 SkillResource
var ultimate_resource: SkillResource = null

## 英雄属性组件引用
var _stats: StatsComponent = null

## 英雄完整数据缓存
var _hero_data: Dictionary = {}

## 技能资源注册表 { skill_id: 脚本路径 }
static var _skill_registry: Dictionary = {
	# 白狼骑士
	"wolf_rush": "res://scripts/combat/skills/wolf_rush.gd",
	"wolf_howl": "res://scripts/combat/skills/wolf_howl.gd",
	"wolf_form": "res://scripts/combat/skills/wolf_form.gd",
	# 流星法师
	"meteor_shower": "res://scripts/combat/skills/meteor_shower.gd",
	"comet_strike": "res://scripts/combat/skills/comet_strike.gd",
	"celestial_fall": "res://scripts/combat/skills/celestial_fall.gd",
	# 辉石法师
	"prism_refract": "res://scripts/combat/skills/prism_refract.gd",
	"gem_cage": "res://scripts/combat/skills/gem_cage.gd",
	"rainbow_prism": "res://scripts/combat/skills/rainbow_prism.gd",
	# 重力法师
	"gravity_well": "res://scripts/combat/skills/gravity_well.gd",
	"gravity_flip": "res://scripts/combat/skills/gravity_flip.gd",
	"singularity_collapse": "res://scripts/combat/skills/singularity_collapse.gd",
}

# ============================================================
# 初始化
# ============================================================

## 从英雄数据初始化技能系统
func initialize(hero_node: Node2D, hero_data: Dictionary) -> void:
	hero = hero_node
	_hero_data = hero_data

	# 获取 StatsComponent
	if hero.has_node("StatsComponent"):
		_stats = hero.get_node("StatsComponent")

	# 解析技能列表
	var skill_list: Array = hero_data.get("skills", [])
	skills.clear()
	ultimate_data = {}
	ultimate_resource = null

	for skill: Dictionary in skill_list:
		var skill_type: String = skill.get("type", "")
		var sid: String = skill.get("id", "")

		match skill_type:
			"active":
				var slot: int = int(skill.get("slot", 0))
				var cd: float = float(skill.get("cooldown", 10.0))
				var res: SkillResource = _load_skill_resource(sid)
				if res:
					res.cooldown = cd
				skills[sid] = {
					"data": skill,
					"resource": res,
					"cooldown_remaining": 0.0,
					"cooldown_total": cd,
					"is_ready": true,
					"slot": slot,
				}
			"ultimate":
				ultimate_data = skill
				var charge_cond: Dictionary = skill.get("charge_condition", {})
				ultimate_charge_type = charge_cond.get("type", "kill_count")
				ultimate_max_charge = float(charge_cond.get("value", 50))
				ultimate_charge = 0.0
				ultimate_resource = _load_skill_resource(sid)

	# 连接蓄力信号
	_connect_charge_signals()

# ============================================================
# 帧处理
# ============================================================

func _process(delta: float) -> void:
	if hero == null:
		return

	# 更新所有技能冷却
	for sid: String in skills:
		var skill_entry: Dictionary = skills[sid]
		if skill_entry["cooldown_remaining"] > 0.0:
			skill_entry["cooldown_remaining"] = maxf(skill_entry["cooldown_remaining"] - delta, 0.0)
			var slot: int = skill_entry["slot"]
			cooldown_updated.emit(slot, skill_entry["cooldown_remaining"], skill_entry["cooldown_total"])

			if skill_entry["cooldown_remaining"] <= 0.0 and not skill_entry["is_ready"]:
				skill_entry["is_ready"] = true
				skill_ready.emit(sid)

# ============================================================
# 技能可用性
# ============================================================

## 指定槽位的技能是否可用（slot 1 或 2）
func can_use_skill(slot: int) -> bool:
	for sid: String in skills:
		var entry: Dictionary = skills[sid]
		if entry["slot"] == slot:
			return entry["is_ready"]
	return false


## 释放指定槽位的技能
func use_skill(slot: int) -> void:
	for sid: String in skills:
		var entry: Dictionary = skills[sid]
		if entry["slot"] == slot and entry["is_ready"]:
			entry["is_ready"] = false
			entry["cooldown_remaining"] = entry["cooldown_total"]

			var res: SkillResource = entry.get("resource") as SkillResource
			if res:
				res.execute(hero, _stats, self)
			else:
				push_warning("SkillSystem: 技能 '%s' 无 SkillResource 实例" % sid)

			skill_used.emit(sid)
			cooldown_updated.emit(slot, entry["cooldown_remaining"], entry["cooldown_total"])
			return

# ============================================================
# 终极技蓄力
# ============================================================

## 增加终极技蓄力值
func add_ultimate_charge(amount: float) -> void:
	if ultimate_data.is_empty():
		return

	var prev_charge: float = ultimate_charge
	ultimate_charge = minf(ultimate_charge + amount, ultimate_max_charge)

	if prev_charge < ultimate_max_charge and ultimate_charge >= ultimate_max_charge:
		ultimate_charged.emit()


## 终极技是否可释放
func can_use_ultimate() -> bool:
	if ultimate_data.is_empty():
		return false
	return ultimate_charge >= ultimate_max_charge


## 释放终极技
func use_ultimate() -> void:
	if not can_use_ultimate():
		return

	ultimate_charge = 0.0

	if ultimate_resource:
		ultimate_resource.execute(hero, _stats, self)
	else:
		var sid: String = ultimate_data.get("id", "")
		push_warning("SkillSystem: 终极技 '%s' 无 SkillResource 实例" % sid)

	ultimate_used.emit()

# ============================================================
# 技能资源加载
# ============================================================

## 根据 skill_id 加载对应的 SkillResource 实例
func _load_skill_resource(sid: String) -> SkillResource:
	var path: String = _skill_registry.get(sid, "")
	if path == "":
		push_warning("SkillSystem: 技能注册表中未找到 '%s'" % sid)
		return null
	if not ResourceLoader.exists(path):
		push_warning("SkillSystem: 技能脚本不存在 '%s'" % path)
		return null
	var script: GDScript = load(path) as GDScript
	if script == null:
		return null
	return script.new() as SkillResource

# ============================================================
# 效果应用（供 SkillResource 脚本调用）
# ============================================================

## 对目标造成技能伤害
func _deal_skill_damage(target: Node2D, raw_damage: float) -> void:
	if not is_instance_valid(target):
		return

	var target_stats: StatsComponent = null
	if target.has_node("StatsComponent"):
		target_stats = target.get_node("StatsComponent")
	if target_stats == null:
		return

	# 应用卡牌全局技能伤害倍率
	var card_damage_mult: float = CardEffects.get_skill_damage_multiplier(self)
	var modified_damage: float = raw_damage * card_damage_mult

	# 伤害公式：max(modified_damage - defense, 1)
	var defense: float = target_stats.get_stat("defense")
	var final_damage: int = maxi(int(modified_damage - defense), 1)
	target_stats.take_damage(float(final_damage))

	# 记录伤害
	var gm: Node = _get_game_manager()
	if gm and gm.has_method("record_damage"):
		gm.record_damage(float(final_damage))

	# 飘字
	if DamageSystem and DamageSystem.has_method("create_damage_number"):
		DamageSystem.create_damage_number(target.global_position, final_damage, false)

	# 终极技蓄力（伤害型）
	if ultimate_charge_type == "damage_dealt":
		add_ultimate_charge(float(final_damage))


## 对目标施加减速效果
func _apply_slow(target: Node2D, slow_percent: float, duration: float) -> void:
	if not is_instance_valid(target):
		return
	if not target.has_node("StatsComponent"):
		return

	var target_stats: StatsComponent = target.get_node("StatsComponent")
	var current_speed: float = target_stats.get_stat("speed")
	var slow_amount: float = -current_speed * slow_percent
	var source_id: String = "skill_slow_%d" % target.get_instance_id()

	target_stats.add_modifier("speed", source_id, slow_amount)

	if hero and hero.is_inside_tree():
		hero.get_tree().create_timer(duration).timeout.connect(
			func() -> void:
				if is_instance_valid(target) and target.has_node("StatsComponent"):
					var ts: StatsComponent = target.get_node("StatsComponent")
					ts.remove_modifier("speed", source_id)
		)


## 对目标施加恐惧效果（反向移动）
func _apply_fear(target: Node2D, duration: float) -> void:
	if not is_instance_valid(target):
		return

	if "is_feared" in target:
		target.is_feared = true
	else:
		target.set_meta("is_feared", true)

	if hero and hero.is_inside_tree():
		hero.get_tree().create_timer(duration).timeout.connect(
			func() -> void:
				if is_instance_valid(target):
					if "is_feared" in target:
						target.is_feared = false
					else:
						target.set_meta("is_feared", false)
		)


## 对目标施加击退效果
func _apply_knockback(target: Node2D, direction: Vector2, force: float) -> void:
	if not is_instance_valid(target):
		return

	var knockback_offset: Vector2 = direction.normalized() * force
	var target_pos: Vector2 = target.global_position

	var tween: Tween = target.create_tween()
	tween.tween_property(target, "global_position", target_pos + knockback_offset, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

# ============================================================
# 终极技蓄力信号连接
# ============================================================

func _connect_charge_signals() -> void:
	if hero == null or not hero.is_inside_tree():
		if hero:
			hero.ready.connect(_connect_charge_signals, CONNECT_ONE_SHOT)
		return

	var gm: Node = _get_game_manager()
	if gm == null:
		return

	match ultimate_charge_type:
		"kill_count":
			if gm.has_signal("kill_recorded"):
				if not gm.kill_recorded.is_connected(_on_kill_recorded):
					gm.kill_recorded.connect(_on_kill_recorded)
		"damage_dealt":
			pass  # 在 _deal_skill_damage 中主动调用
		"skill_hit":
			pass  # 在各 SkillResource.execute 中主动调用
		"pull_count":
			pass  # 在重力法师技能中主动调用


func _on_kill_recorded(_total_kills: int) -> void:
	if ultimate_charge_type == "kill_count":
		add_ultimate_charge(1.0)

# ============================================================
# 工具方法
# ============================================================

func _get_game_manager() -> Node:
	return GameManager


func _get_nearest_enemy() -> Node2D:
	if hero == null or not hero.is_inside_tree():
		return null

	var nearest: Node2D = null
	var nearest_dist: float = INF

	var enemies: Array[Node] = hero.get_tree().get_nodes_in_group("enemies")
	for node: Node in enemies:
		if node is Node2D and is_instance_valid(node):
			var enemy: Node2D = node as Node2D
			if enemy.has_node("StatsComponent"):
				var enemy_stats: StatsComponent = enemy.get_node("StatsComponent")
				if not enemy_stats.is_alive():
					continue
			var dist: float = hero.global_position.distance_squared_to(enemy.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = enemy

	return nearest


func _get_enemies_in_radius(center: Vector2, radius: float) -> Array:
	var result: Array = []
	if hero == null or not hero.is_inside_tree():
		return result

	var enemies: Array[Node] = hero.get_tree().get_nodes_in_group("enemies")
	for node: Node in enemies:
		if node is Node2D and is_instance_valid(node):
			var enemy: Node2D = node as Node2D
			if enemy.has_node("StatsComponent"):
				var enemy_stats: StatsComponent = enemy.get_node("StatsComponent")
				if not enemy_stats.is_alive():
					continue
			var dist: float = center.distance_to(enemy.global_position)
			if dist <= radius:
				result.append(enemy)

	return result


func _get_enemies_on_path(start: Vector2, end: Vector2, half_width: float) -> Array:
	var result: Array = []
	if hero == null or not hero.is_inside_tree():
		return result

	var path_dir: Vector2 = (end - start).normalized()
	var path_length: float = start.distance_to(end)
	var path_normal: Vector2 = Vector2(-path_dir.y, path_dir.x)

	var enemies: Array[Node] = hero.get_tree().get_nodes_in_group("enemies")
	for node: Node in enemies:
		if node is Node2D and is_instance_valid(node):
			var enemy: Node2D = node as Node2D
			if enemy.has_node("StatsComponent"):
				var enemy_stats: StatsComponent = enemy.get_node("StatsComponent")
				if not enemy_stats.is_alive():
					continue

			var to_enemy: Vector2 = enemy.global_position - start
			var proj_along: float = to_enemy.dot(path_dir)
			var proj_perp: float = absf(to_enemy.dot(path_normal))

			if proj_along >= 0.0 and proj_along <= path_length and proj_perp <= half_width:
				result.append(enemy)

	return result
