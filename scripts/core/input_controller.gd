class_name InputController
extends Node
## InputController -- 输入处理逻辑
## 从 GameSession 抽取，支持多玩家输入分发。

# ============================================================
# 信号
# ============================================================

signal building_hotkey_pressed(building_id: String)
signal pause_requested()

# ============================================================
# 玩家输入配置（P1: WASD+QER, P2: 方向键+JKL）
# ============================================================

var player_configs: Array[Dictionary] = [
	{
		"id": 0,
		"move_up": "move_up", "move_down": "move_down",
		"move_left": "move_left", "move_right": "move_right",
		"skill_1": "skill_1", "skill_2": "skill_2",
		"ultimate": "ultimate",
	},
	{
		"id": 1,
		"move_up": "p2_move_up", "move_down": "p2_move_down",
		"move_left": "p2_move_left", "move_right": "p2_move_right",
		"skill_1": "p2_skill_1", "skill_2": "p2_skill_2",
		"ultimate": "p2_ultimate",
	},
]

## 玩家 → 英雄映射
var player_heroes: Dictionary = {}  # { 0: HeroBase, 1: HeroBase }

## 塔放置系统引用（用于建筑快捷键）
var tower_placement: TowerPlacement = null

# ============================================================
# 公共接口
# ============================================================

## 注册玩家英雄映射
func register_hero(player_id: int, hero: HeroBase) -> void:
	player_heroes[player_id] = hero


## 获取指定玩家的移动方向
func get_movement(player_id: int) -> Vector2:
	if player_id < 0 or player_id >= player_configs.size():
		return Vector2.ZERO
	var cfg: Dictionary = player_configs[player_id]
	var direction := Vector2.ZERO
	if Input.is_action_pressed(cfg["move_up"]):
		direction.y -= 1
	if Input.is_action_pressed(cfg["move_down"]):
		direction.y += 1
	if Input.is_action_pressed(cfg["move_left"]):
		direction.x -= 1
	if Input.is_action_pressed(cfg["move_right"]):
		direction.x += 1
	return direction.normalized()


## 处理所有玩家输入（每帧调用）
func process_input() -> void:
	for player_id: int in player_heroes:
		var hero_ref = player_heroes[player_id]
		if not is_instance_valid(hero_ref):
			continue
		var hero: HeroBase = hero_ref as HeroBase
		if hero == null:
			continue

		# 移动
		hero.set_move_direction(get_movement(player_id))

		# 技能
		var cfg: Dictionary = player_configs[player_id]
		var skill_sys: SkillSystem = _get_skill_system(hero)
		if skill_sys:
			if Input.is_action_just_pressed(cfg["skill_1"]):
				if skill_sys.can_use_skill(1):
					skill_sys.use_skill(1)
			if Input.is_action_just_pressed(cfg["skill_2"]):
				if skill_sys.can_use_skill(2):
					skill_sys.use_skill(2)
			if Input.is_action_just_pressed(cfg["ultimate"]):
				if skill_sys.can_use_ultimate():
					skill_sys.use_ultimate()

	# 建筑放置快捷键（数字键 1-3，仅触发一次）
	if Input.is_action_just_pressed("build_1"):
		building_hotkey_pressed.emit("arrow_tower")
	elif Input.is_action_just_pressed("build_2"):
		building_hotkey_pressed.emit("gold_mine")
	elif Input.is_action_just_pressed("build_3"):
		building_hotkey_pressed.emit("barracks")


## 处理 ESC 等未处理输入
func handle_unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if tower_placement and tower_placement.is_placing:
			tower_placement.cancel_placement()
		else:
			pause_requested.emit()


# ============================================================
# 内部辅助
# ============================================================

func _get_skill_system(hero: HeroBase) -> SkillSystem:
	for child: Node in hero.get_children():
		if child is SkillSystem:
			return child as SkillSystem
	return null
