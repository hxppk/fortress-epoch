extends Node2D
## 游戏会话顶层控制器
## 管理英雄生成、波次流程、建筑放置、输入分发

# 场景预加载
const WolfKnightScene := preload("res://scenes/entities/heroes/wolf_knight.tscn")
const MeteorMageScene := preload("res://scenes/entities/heroes/meteor_mage.tscn")

# 节点引用
@onready var map: Node2D = $Map
@onready var heroes_node: Node2D = $Entities/Heroes
@onready var enemies_node: Node2D = $Entities/Enemies
@onready var buildings_node: Node2D = $Entities/Buildings
@onready var camera: Camera2D = $Camera2D
@onready var ui_layer: CanvasLayer = $UI
@onready var wave_spawner: WaveSpawner = $WaveSpawner
@onready var enemy_pool: EnemyPool = $EnemyPool
@onready var tower_placement: TowerPlacement = $TowerPlacement
@onready var hud: Control = $UI/HUD
@onready var building_selection: Control = $UI/BuildingSelection
@onready var building_upgrade_panel: Control = $UI/BuildingUpgradePanel

# 游戏状态
var current_hero: HeroBase = null
var skill_system: SkillSystem = null
var auto_attack: AutoAttackComponent = null

# 堡垒核心位置（地图中心偏下）
var fortress_position := Vector2(240, 200)

# 出生点
var spawn_points := {
	"north": Vector2(240, -20),
	"east": Vector2(500, 150),
	"south": Vector2(240, 420),
	"west": Vector2(-20, 150),
}


func _ready() -> void:
	_setup_game()


func _setup_game() -> void:
	# 初始化 GameManager
	GameManager.start_game()

	# 初始化敌人对象池
	enemy_pool.initialize(enemies_node)

	# 初始化波次生成器
	wave_spawner.initialize(enemy_pool, fortress_position)
	wave_spawner.set_spawn_points(spawn_points)
	wave_spawner.wave_started.connect(_on_wave_started)
	wave_spawner.wave_completed.connect(_on_wave_completed)
	wave_spawner.all_waves_completed.connect(_on_all_waves_completed)

	# 初始化塔放置系统
	tower_placement.placeable_area = Rect2i(2, 2, 26, 22)
	tower_placement.building_placed.connect(_on_building_placed)

	# 建筑选择 UI 信号
	if building_selection and building_selection.has_signal("building_selected"):
		building_selection.building_selected.connect(_on_building_selection_made)

	# 城镇升级信号 -> 触发建筑选择
	if GameManager.has_signal("town_level_up"):
		GameManager.town_level_up.connect(_on_town_level_up)

	# 生成英雄
	_spawn_hero()

	# 加载第一阶段
	wave_spawner.load_stage("stage_1_tutorial")

	# 延迟启动第一波
	await get_tree().create_timer(1.0).timeout
	wave_spawner.start_next_wave()


func _spawn_hero() -> void:
	current_hero = WolfKnightScene.instantiate() as HeroBase
	heroes_node.add_child(current_hero)
	current_hero.global_position = fortress_position + Vector2(0, -30)
	current_hero.initialize("wolf_knight")
	current_hero.add_to_group("heroes")

	# 设置技能系统
	skill_system = SkillSystem.new()
	current_hero.add_child(skill_system)
	skill_system.initialize(current_hero, current_hero.hero_data)

	# 设置自动攻击组件
	auto_attack = AutoAttackComponent.new()
	current_hero.add_child(auto_attack)
	var attack_data: Dictionary = current_hero.hero_data.get("auto_attack", {})
	auto_attack.attack_pattern = attack_data.get("pattern", "single_target")
	auto_attack.fan_angle = attack_data.get("angle", 120.0)
	auto_attack.aoe_radius = attack_data.get("radius", 32.0)
	auto_attack.hit_count_threshold = attack_data.get("hit_count_threshold", 0)
	auto_attack.threshold_effect = attack_data.get("on_threshold_effect", "")
	var stats_comp: StatsComponent = current_hero.get_node("StatsComponent")
	var attack_area: Area2D = current_hero.get_node("AttackArea")
	auto_attack.initialize(current_hero, stats_comp, attack_area)

	# 相机跟随英雄
	camera.reparent(current_hero)
	camera.position = Vector2.ZERO


func _process(_delta: float) -> void:
	if GameManager.game_state != "playing":
		return
	_handle_input()


func _handle_input() -> void:
	if current_hero == null:
		return

	# 移动输入
	var direction := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		direction.y -= 1
	if Input.is_action_pressed("move_down"):
		direction.y += 1
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_right"):
		direction.x += 1
	current_hero.set_move_direction(direction.normalized())

	# 技能输入
	if skill_system:
		if Input.is_action_just_pressed("skill_1"):
			if skill_system.can_use_skill(1):
				skill_system.use_skill(1)
		if Input.is_action_just_pressed("skill_2"):
			if skill_system.can_use_skill(2):
				skill_system.use_skill(2)
		if Input.is_action_just_pressed("ultimate"):
			if skill_system.can_use_ultimate():
				skill_system.use_ultimate()

	# 建筑放置快捷键（数字键 1-3）
	if Input.is_key_pressed(KEY_1):
		tower_placement.start_placement("arrow_tower")
	elif Input.is_key_pressed(KEY_2):
		tower_placement.start_placement("gold_mine")
	elif Input.is_key_pressed(KEY_3):
		tower_placement.start_placement("barracks")


func _on_wave_started(wave_index: int, wave_label: String) -> void:
	print("[GameSession] 波次 %d 开始: %s" % [wave_index + 1, wave_label])
	_update_wave_hud(wave_index, wave_label)


func _on_wave_completed(wave_index: int, rewards: Dictionary) -> void:
	print("[GameSession] 波次 %d 完成! 奖励: %s" % [wave_index + 1, str(rewards)])
	GameManager.game_state = "wave_clear"

	# 波间休息 3 秒
	await get_tree().create_timer(3.0).timeout

	if not wave_spawner.is_all_waves_complete():
		GameManager.game_state = "playing"
		wave_spawner.start_next_wave()
	else:
		_on_all_waves_completed(wave_spawner.current_stage_data.get("id", ""))


func _on_all_waves_completed(stage_id: String) -> void:
	print("[GameSession] 阶段 %s 全部完成!" % stage_id)
	GameManager.end_game(true)


func _update_wave_hud(wave_index: int, label: String) -> void:
	if hud and hud.has_method("update_wave_info"):
		hud.update_wave_info(wave_index + 1, label)


func _on_building_placed(building: Node, _grid_pos: Variant) -> void:
	# 注册到 BuildingManager
	var bm := get_node_or_null("/root/BuildingManager")
	if bm and bm.has_method("register_building"):
		bm.register_building(building)


func _on_town_level_up(new_level: int) -> void:
	print("[GameSession] 城镇升级到 Lv.%d! 触发建筑选择" % new_level)
	# 城镇升级时弹出三选一建筑选择
	if building_selection and building_selection.has_method("show_selection"):
		building_selection.show_selection(["arrow_tower", "gold_mine", "barracks"])


func _on_building_selection_made(building_id: String) -> void:
	print("[GameSession] 玩家选择建筑: %s" % building_id)
	# 选择后进入放置模式
	tower_placement.start_placement(building_id)
