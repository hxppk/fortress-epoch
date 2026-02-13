class_name NPCUnit
extends CharacterBody2D
## NPCUnit — 建筑满3自动生成的NPC单位
## 在对应建筑附近巡逻并自动攻击敌人。

signal npc_died(npc: NPCUnit)

@onready var stats: StatsComponent = $StatsComponent
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var attack_area: Area2D = $AttackArea
@onready var attack_range_shape: CollisionShape2D = $AttackArea/AttackRange
@onready var name_label: Label = $Label

## NPC 类型: "archer", "knight", "miner"
var npc_type: String = ""

## 巡逻中心点
var patrol_center: Vector2 = Vector2.ZERO

## 巡逻半径
var patrol_radius: float = 50.0

## 当前巡逻目标
var _patrol_target: Vector2 = Vector2.ZERO

## 巡逻空闲计时器
var _idle_timer: float = 0.0

## 是否在空闲状态
var _is_idle: bool = true

## 空闲时间
var _idle_duration: float = 1.5

## 到达目标距离
const ARRIVAL_DISTANCE: float = 8.0

## 面朝方向
var facing_right: bool = true

## AutoAttackComponent 引用
var auto_attack: AutoAttackComponent = null

## 出征模式
var expedition_mode: bool = false
## 出征目标 X 坐标
var expedition_target_x: float = 420.0


func _ready() -> void:
	stats.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	if expedition_mode:
		_expedition_move(delta)
	else:
		_patrol(delta)
	move_and_slide()


func _process(_delta: float) -> void:
	# Bobbing 动画
	sprite.position.y = sin(Time.get_ticks_msec() / 1000.0 * 3.0) * 1.0

	# 面朝方向
	if velocity.length_squared() > 1.0:
		facing_right = velocity.x > 0.0
	sprite.flip_h = not facing_right


## 初始化 NPC
func initialize(type: String, npc_stats: Dictionary, center: Vector2, attack_range: float = 40.0, attack_pattern: String = "single_target") -> void:
	npc_type = type
	patrol_center = center

	# 初始化属性
	stats.initialize(npc_stats)

	# 设置攻击范围
	if attack_range_shape and attack_range_shape.shape is CircleShape2D:
		attack_range_shape.shape = attack_range_shape.shape.duplicate()
		attack_range_shape.shape.radius = attack_range

	# 创建精灵（彩色方块）
	_create_sprite()

	# 设置标签
	var type_names: Dictionary = {"archer": "弓箭手", "knight": "骑士", "miner": "矿工"}
	name_label.text = type_names.get(type, type)

	# 创建 AutoAttackComponent
	auto_attack = AutoAttackComponent.new()
	auto_attack.attack_pattern = attack_pattern
	add_child(auto_attack)
	auto_attack.initialize(self, stats, attack_area)

	# 初始化巡逻
	global_position = center
	_pick_new_patrol_target()


func _create_sprite() -> void:
	var sprite_paths: Dictionary = {
		"archer": "res://assets/sprites/npcs/archer.png",
		"knight": "res://assets/sprites/npcs/knight_npc.png",
		"miner": "res://assets/sprites/npcs/miner.png",
	}

	var path: String = sprite_paths.get(npc_type, "")
	if path != "" and ResourceLoader.exists(path):
		sprite.texture = load(path)
	else:
		# 备用：彩色方块
		var color: Color
		match npc_type:
			"archer":
				color = Color(0.3, 0.8, 0.3)
			"knight":
				color = Color(0.3, 0.5, 0.9)
			"miner":
				color = Color(0.9, 0.7, 0.2)
			_:
				color = Color.WHITE
		var image: Image = Image.create(12, 12, false, Image.FORMAT_RGBA8)
		image.fill(color)
		sprite.texture = ImageTexture.create_from_image(image)


# ============================================================
# 巡逻 AI
# ============================================================

func _patrol(delta: float) -> void:
	if _is_idle:
		_idle_timer += delta
		if _idle_timer >= _idle_duration:
			_is_idle = false
			_pick_new_patrol_target()
		velocity = velocity.move_toward(Vector2.ZERO, 200.0 * delta)
		return

	var distance: float = global_position.distance_to(_patrol_target)
	if distance <= ARRIVAL_DISTANCE:
		_is_idle = true
		_idle_timer = 0.0
		_idle_duration = randf_range(1.0, 3.0)
		velocity = Vector2.ZERO
		return

	var direction: Vector2 = (_patrol_target - global_position).normalized()
	var speed: float = stats.get_stat("speed")
	velocity = direction * speed


func _pick_new_patrol_target() -> void:
	var angle: float = randf() * TAU
	var dist: float = randf() * patrol_radius
	_patrol_target = patrol_center + Vector2(cos(angle), sin(angle)) * dist
	# Clamp to map bounds (world is 480x270)
	_patrol_target.x = clampf(_patrol_target.x, 10.0, 470.0)
	_patrol_target.y = clampf(_patrol_target.y, 10.0, 260.0)


## 进入出征模式
func enter_expedition(spawn_pos: Vector2, target_x: float) -> void:
	expedition_mode = true
	expedition_target_x = target_x
	global_position = spawn_pos
	_is_idle = false
	velocity = Vector2.ZERO
	# Clear auto attack targets (they're from defense mode)
	if auto_attack:
		auto_attack.targets_in_range.clear()


## 退出出征模式，恢复巡逻
func exit_expedition(restore_pos: Vector2, restore_center: Vector2) -> void:
	expedition_mode = false
	global_position = restore_pos
	patrol_center = restore_center
	_is_idle = true
	_idle_timer = 0.0
	velocity = Vector2.ZERO
	# Restore full HP
	if stats and not stats.is_alive():
		# Re-enable processing if was dead
		set_physics_process(true)
		set_process(true)
		modulate.a = 1.0
	if stats:
		stats.current_hp = stats.max_hp
		stats.health_changed.emit(stats.current_hp, stats.max_hp)
	# Clear auto attack targets
	if auto_attack:
		auto_attack.targets_in_range.clear()


## 出征模式移动：向右推进
func _expedition_move(delta: float) -> void:
	var speed: float = stats.get_stat("speed")
	if global_position.x < expedition_target_x - 20.0:
		velocity = Vector2(speed, 0)
	else:
		# Reached target area, stop and let auto_attack do the work
		velocity = velocity.move_toward(Vector2.ZERO, 200.0 * delta)


func _on_died() -> void:
	npc_died.emit(self)
	set_physics_process(false)
	set_process(false)
	if expedition_mode:
		# 出征中死亡：只淡出，不销毁，等 exit_expedition() 复活
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.5)
	else:
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.5)
		tween.tween_callback(queue_free)
