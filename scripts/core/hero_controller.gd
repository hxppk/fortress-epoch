class_name HeroController
extends Node
## HeroController -- 英雄选择、生成与管理
## 数据驱动的英雄注册表，替代 GameSession 中的硬编码预加载。

# ============================================================
# 信号
# ============================================================

signal hero_selected(hero_id: String)
signal hero_spawned(hero: HeroBase)

# ============================================================
# 属性
# ============================================================

## 可用英雄场景注册表（数据驱动）
var hero_scenes: Dictionary = {
	"wolf_knight": "res://scenes/entities/heroes/wolf_knight.tscn",
	"meteor_mage": "res://scenes/entities/heroes/meteor_mage.tscn",
	"crystal_mage": "res://scenes/entities/heroes/crystal_mage.tscn",
	"gravity_mage": "res://scenes/entities/heroes/gravity_mage.tscn",
}

## 当前激活的英雄列表
var current_heroes: Array[HeroBase] = []

## 英雄的父节点
var heroes_parent: Node2D = null

## 当前主英雄（单人模式）
var primary_hero: HeroBase = null

# ============================================================
# 公共接口
# ============================================================

## 获取所有可用英雄 ID 列表
func get_available_hero_ids() -> Array[String]:
	var ids: Array[String] = []
	for hero_id: String in hero_scenes:
		ids.append(hero_id)
	return ids


## 生成英雄（返回生成的 HeroBase 实例）
func spawn_hero(hero_id: String, pos: Vector2, parent: Node2D = null) -> HeroBase:
	var target_parent: Node2D = parent if parent else heroes_parent
	if target_parent == null:
		push_error("HeroController: heroes_parent 未设置")
		return null

	var scene_path: String = hero_scenes.get(hero_id, "")
	if scene_path == "":
		push_error("HeroController: 未知英雄 ID '%s'" % hero_id)
		return null

	if not ResourceLoader.exists(scene_path):
		push_error("HeroController: 英雄场景不存在 '%s'" % scene_path)
		return null

	var scene: PackedScene = load(scene_path)
	var hero: HeroBase = scene.instantiate() as HeroBase
	target_parent.add_child(hero)
	hero.global_position = pos
	hero.initialize(hero_id)
	hero.add_to_group("heroes")

	# 应用局外加成
	if GameManager.has_method("apply_meta_bonuses_to_hero"):
		GameManager.apply_meta_bonuses_to_hero(hero)

	# 设置技能系统
	var skill_system: SkillSystem = SkillSystem.new()
	hero.add_child(skill_system)
	skill_system.initialize(hero, hero.hero_data)

	# 设置自动攻击组件
	var auto_attack: AutoAttackComponent = AutoAttackComponent.new()
	hero.add_child(auto_attack)
	var attack_data: Dictionary = hero.hero_data.get("auto_attack", {})
	auto_attack.attack_pattern = attack_data.get("pattern", "single_target")
	auto_attack.fan_angle = float(attack_data.get("angle", 120.0))
	auto_attack.aoe_radius = float(attack_data.get("radius", 32.0))
	auto_attack.hit_count_threshold = int(attack_data.get("hit_count_threshold", 0))
	auto_attack.threshold_effect = attack_data.get("on_threshold_effect", "")
	var stats_comp: StatsComponent = hero.get_node("StatsComponent")
	var attack_area: Area2D = hero.get_node("AttackArea")
	auto_attack.initialize(hero, stats_comp, attack_area)

	current_heroes.append(hero)
	if primary_hero == null:
		primary_hero = hero

	hero_spawned.emit(hero)
	return hero


## 获取主英雄的 SkillSystem（用于输入分发）
func get_skill_system(hero: HeroBase = null) -> SkillSystem:
	var target: HeroBase = hero if hero else primary_hero
	if target == null:
		return null
	for child: Node in target.get_children():
		if child is SkillSystem:
			return child as SkillSystem
	return null


## 获取主英雄的 AutoAttackComponent
func get_auto_attack(hero: HeroBase = null) -> AutoAttackComponent:
	var target: HeroBase = hero if hero else primary_hero
	if target == null:
		return null
	for child: Node in target.get_children():
		if child is AutoAttackComponent:
			return child as AutoAttackComponent
	return null
