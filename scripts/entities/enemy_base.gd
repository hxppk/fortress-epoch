class_name EnemyBase
extends CharacterBody2D
## EnemyBase — 敌人基类
## AI 移动 + 仇恨目标选择 + 攻击 + 掉落。所有敌人共享此脚本，通过 behavior 区分行为。

# ============================================================
# 信号
# ============================================================

signal enemy_died(enemy: EnemyBase)
signal reached_target()
signal enraged(count: int)

# ============================================================
# 导出属性
# ============================================================

@export var enemy_id: String = ""

# ============================================================
# 属性
# ============================================================

## 从 enemies.json 加载的完整数据
var enemy_data: Dictionary = {}

## 行为类型
var behavior: String = "straight_charge"

## 当前目标节点（英雄 / 建筑 / 堡垒核心）
var target: Node2D = null

## 移动目标点（堡垒方向，默认目的地）
var move_target: Vector2 = Vector2.ZERO

## 对象池：是否激活
var is_active: bool = false

## 面朝方向
var facing_right: bool = true

## 狂暴次数（兽人精英用）
var enrage_count: int = 0

## 恶魔 BOSS：当前阶段索引
var _current_phase: int = 0

## 狂暴阈值记录（已触发的索引）
var _enrage_thresholds_triggered: Array[bool] = []

## 攻击计时器
var _attack_timer: float = 0.0

## 基础攻击间隔（秒）
var _base_attack_interval: float = 1.5

## 到达目标的距离阈值
const ARRIVAL_DISTANCE: float = 10.0

## 仇恨系统：检测范围（像素）
const AGGRO_RANGE: float = 120.0

## 仇恨系统：攻击射程（像素，进入此距离后停下攻击）
const ATTACK_RANGE: float = 24.0

## 仇恨目标刷新间隔（秒），避免每帧扫描
var _aggro_refresh_timer: float = 0.0
const AGGRO_REFRESH_INTERVAL: float = 0.3

# ============================================================
# 子节点引用
# ============================================================

@onready var stats: StatsComponent = $StatsComponent
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	# 连接 stats 死亡信号
	stats.died.connect(_on_stats_died)
	stats.health_changed.connect(_on_health_changed)

	# 若 enemy_id 已在编辑器中设置，加载数据
	if enemy_id != "":
		_load_data_from_json()

	# NavigationAgent2D 设置（可选，nav_agent 可能为 null）
	if nav_agent:
		nav_agent.path_desired_distance = 4.0
		nav_agent.target_desired_distance = 4.0


func _physics_process(delta: float) -> void:
	if not is_active:
		return

	# 定期刷新仇恨目标
	_aggro_refresh_timer -= delta
	if _aggro_refresh_timer <= 0.0:
		_aggro_refresh_timer = AGGRO_REFRESH_INTERVAL
		_update_aggro_target()

	_execute_behavior(delta)
	move_and_slide()


func _process(_delta: float) -> void:
	if not is_active:
		return

	# Bobbing 动画
	sprite.position.y = sin(Time.get_ticks_msec() / 1000.0 * 4.0) * 1.5

	# 面朝方向
	if velocity.length_squared() > 1.0:
		facing_right = velocity.x > 0.0
	sprite.flip_h = not facing_right

# ============================================================
# 初始化 & 对象池
# ============================================================

## 用数据字典初始化敌人属性
func initialize(id: String, data: Dictionary) -> void:
	enemy_id = id
	enemy_data = data.duplicate(true)
	behavior = data.get("behavior", "straight_charge")

	# 初始化 stats 组件
	var stat_data: Dictionary = data.get("stats", {})
	stats.initialize(stat_data)

	# 加载精灵纹理
	var sprite_path: String = data.get("sprite", "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)

	# 初始化攻击间隔（用速度反算，速度越快间隔越短）
	var spd: float = stats.get_stat("speed")
	_base_attack_interval = 1.5 if spd <= 0.0 else maxf(0.5, 2.0 - spd / 100.0)

	# 狂暴阈值（兽人精英）
	if data.has("enrage_thresholds"):
		var thresholds: Array = data["enrage_thresholds"]
		_enrage_thresholds_triggered.clear()
		for i in range(thresholds.size()):
			_enrage_thresholds_triggered.append(false)

	# 恶魔 BOSS 阶段
	_current_phase = 0
	enrage_count = 0


## 激活敌人（从对象池取出时调用）
func activate(pos: Vector2, target_pos: Vector2) -> void:
	global_position = pos
	move_target = target_pos
	is_active = true
	visible = true
	collision.disabled = false
	_attack_timer = 0.0
	enrage_count = 0
	_current_phase = 0
	_aggro_refresh_timer = 0.0
	target = null

	# 重置狂暴阈值
	for i in range(_enrage_thresholds_triggered.size()):
		_enrage_thresholds_triggered[i] = false

	# 设置导航目标（可选，nav_agent 可能为 null）
	if nav_agent:
		nav_agent.target_position = target_pos

	# 重新初始化 stats
	if enemy_data.has("stats"):
		stats.initialize(enemy_data["stats"])


## 停用敌人（回收到对象池）
func deactivate() -> void:
	is_active = false
	visible = false
	collision.disabled = true
	velocity = Vector2.ZERO
	target = null
	global_position = Vector2(-9999, -9999)
	_stop_burn()  # 清除灼烧效果


## 重置为初始状态（对象池复用前调用）
func reset() -> void:
	enrage_count = 0
	_current_phase = 0
	_attack_timer = 0.0
	_aggro_refresh_timer = 0.0
	facing_right = true
	velocity = Vector2.ZERO
	target = null
	sprite.position = Vector2.ZERO
	sprite.flip_h = false

	# 清除所有 modifiers
	if stats:
		stats.modifiers.clear()

	for i in range(_enrage_thresholds_triggered.size()):
		_enrage_thresholds_triggered[i] = false

	_stop_burn()  # 清除灼烧效果

# ============================================================
# 仇恨系统
# ============================================================

## 更新仇恨目标：英雄 > 建筑 > 堡垒（move_target）
func _update_aggro_target() -> void:
	# 优先级1：射程内存活英雄（最近的）
	var hero_target := _find_nearest_in_group("heroes", AGGRO_RANGE)
	if hero_target != null:
		target = hero_target
		return

	# 优先级2：射程内存活建筑（最近的）
	var building_target := _find_nearest_in_group("buildings", AGGRO_RANGE)
	if building_target != null:
		target = building_target
		return

	# 优先级3：无目标，继续向堡垒移动
	target = null


## 在指定 group 中查找距离最近的存活节点
func _find_nearest_in_group(group_name: String, max_range: float) -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null

	var candidates: Array[Node] = tree.get_nodes_in_group(group_name)
	var nearest: Node2D = null
	var nearest_dist_sq: float = max_range * max_range

	for node: Node in candidates:
		if node is not Node2D:
			continue
		var n2d: Node2D = node as Node2D

		# 跳过不可见或已死亡的目标
		if not n2d.visible:
			continue
		if n2d.has_method("is_alive") and not n2d.is_alive():
			continue
		# 也检查 stats 组件
		if n2d.has_node("StatsComponent"):
			var target_stats: StatsComponent = n2d.get_node("StatsComponent") as StatsComponent
			if target_stats != null and not target_stats.is_alive():
				continue

		var dist_sq: float = global_position.distance_squared_to(n2d.global_position)
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = n2d

	return nearest

# ============================================================
# 行为执行
# ============================================================

## 根据 behavior 类型执行不同行为
func _execute_behavior(delta: float) -> void:
	match behavior:
		"straight_charge":
			_move_toward_target(delta)
		"fast_approach":
			_move_toward_target(delta)
		"slow_tank":
			_move_toward_target(delta)
		"charge_and_slash":
			_check_enrage()
			_move_toward_target(delta)
		"two_phase":
			_check_phase_change()
			_move_toward_target(delta)
		_:
			_move_toward_target(delta)


## 向目标移动（含仇恨目标处理）
func _move_toward_target(delta: float) -> void:
	var speed: float = stats.get_stat("speed")

	# 如果有仇恨目标（英雄/建筑），向其移动并攻击
	if target != null and is_instance_valid(target):
		var dist_to_target: float = global_position.distance_to(target.global_position)
		if dist_to_target <= ATTACK_RANGE:
			# 在攻击范围内：停止移动，执行攻击
			velocity = Vector2.ZERO
			_attack_target(delta)
			return
		else:
			# 向仇恨目标移动
			var direction: Vector2 = (target.global_position - global_position).normalized()
			velocity = direction * speed
			return

	# 无仇恨目标：向堡垒（move_target）移动
	var distance_to_fortress: float = global_position.distance_to(move_target)
	if distance_to_fortress <= ARRIVAL_DISTANCE:
		_on_reached_target()
		return

	# 直接朝目标移动（不依赖 NavigationAgent2D）
	var direction: Vector2 = (move_target - global_position).normalized()
	velocity = direction * speed


## 攻击仇恨目标
func _attack_target(delta: float) -> void:
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return

	_attack_timer = _base_attack_interval

	if target == null or not is_instance_valid(target):
		return

	var atk: float = stats.get_stat("attack")

	# 对目标的 StatsComponent 造成伤害
	if target.has_node("StatsComponent"):
		var target_stats: StatsComponent = target.get_node("StatsComponent") as StatsComponent
		if target_stats != null and target_stats.is_alive():
			target_stats.take_damage(atk)

# ============================================================
# 到达目标处理
# ============================================================

func _on_reached_target() -> void:
	reached_target.emit()

	# 对堡垒造成伤害（每个敌人扣1点堡垒生命）
	GameManager.take_shared_damage(1)
	GameManager.record_damage(1)

	# 红色闪屏警告
	if CombatFeedback and CombatFeedback.has_method("screen_red_flash"):
		CombatFeedback.screen_red_flash()
	if CombatFeedback and CombatFeedback.has_method("fortress_flash"):
		CombatFeedback.fortress_flash()

	# 自毁
	die()

# ============================================================
# 死亡 & 掉落
# ============================================================

## 死亡处理
func die() -> void:
	if not is_active:
		return

	_drop_loot()
	GameManager.record_kill()

	# 连杀计数 + 击杀粒子反馈
	if CombatFeedback:
		CombatFeedback.record_kill()
		CombatFeedback.spawn_death_particles(global_position)

	enemy_died.emit(self)
	deactivate()


## 根据 loot 配置计算掉落
func _drop_loot() -> void:
	if not enemy_data.has("loot"):
		return

	var loot: Dictionary = enemy_data["loot"]

	# 金币
	if loot.has("gold"):
		var gold_amount: int = _calc_loot_amount(loot["gold"])
		if gold_amount > 0:
			GameManager.add_resource("gold", gold_amount)

	# 水晶
	if loot.has("crystal"):
		var crystal_amount: int = _calc_loot_amount(loot["crystal"])
		if crystal_amount > 0:
			GameManager.add_resource("crystal", crystal_amount)

	# 水晶概率额外掉落
	if loot.has("crystal_chance") and loot.has("crystal_bonus"):
		var chance: float = float(loot["crystal_chance"])
		if randf() < chance:
			GameManager.add_resource("crystal", int(loot["crystal_bonus"]))

	# 徽章
	if loot.has("badge"):
		var badge_amount: int = _calc_loot_amount(loot["badge"])
		if badge_amount > 0:
			GameManager.add_resource("badge", badge_amount)

	# 徽章概率额外掉落
	if loot.has("badge_chance") and loot.has("badge_bonus"):
		var chance: float = float(loot["badge_chance"])
		if randf() < chance:
			GameManager.add_resource("badge", int(loot["badge_bonus"]))

	# 经验
	if loot.has("exp"):
		var exp_amount: int = _calc_loot_amount(loot["exp"])
		if exp_amount > 0:
			GameManager.add_exp(exp_amount)


## 计算掉落数量：数组 [min, max] 随机，单值直接返回
func _calc_loot_amount(value: Variant) -> int:
	if value is Array:
		var arr: Array = value
		if arr.size() >= 2:
			return randi_range(int(arr[0]), int(arr[1]))
		elif arr.size() == 1:
			return int(arr[0])
		return 0
	return int(value)

# ============================================================
# 狂暴（兽人精英: charge_and_slash）
# ============================================================

## 每损失 25% HP 狂暴一次，攻速 +50%
func _check_enrage() -> void:
	if not enemy_data.has("enrage_thresholds"):
		return

	var hp_ratio: float = stats.current_hp / stats.max_hp
	var thresholds: Array = enemy_data["enrage_thresholds"]
	var bonus: float = enemy_data.get("enrage_attack_speed_bonus", 0.5)

	for i in range(thresholds.size()):
		if i >= _enrage_thresholds_triggered.size():
			break
		if _enrage_thresholds_triggered[i]:
			continue
		var threshold: float = float(thresholds[i])
		if hp_ratio <= threshold:
			_enrage_thresholds_triggered[i] = true
			enrage_count += 1
			# 叠加攻速修改器（用速度模拟攻速）
			var speed_bonus_value: float = stats.get_stat("speed") * bonus
			stats.add_modifier("speed", "enrage_%d" % enrage_count, speed_bonus_value)
			enraged.emit(enrage_count)

# ============================================================
# 阶段切换（恶魔 BOSS: two_phase）
# ============================================================

## 60% HP 进入狂暴阶段：ATK +50%, 攻速(speed) +30%
func _check_phase_change() -> void:
	if _current_phase >= 1:
		return  # 已经在狂暴阶段

	if not enemy_data.has("phases"):
		return

	var phases: Array = enemy_data["phases"]
	if phases.size() < 2:
		return

	var hp_ratio: float = stats.current_hp / stats.max_hp
	var phase_1_data: Dictionary = phases[1]
	var hp_range: Array = phase_1_data.get("hp_range", [0.6, 0.0])
	var phase_threshold: float = float(hp_range[0])

	if hp_ratio <= phase_threshold:
		_current_phase = 1

		# ATK +50%
		var atk_bonus: float = stats.get_stat("attack") * phase_1_data.get("attack_bonus", 0.5)
		stats.add_modifier("attack", "boss_phase_1", atk_bonus)

		# 攻速(speed) +30%
		var speed_bonus: float = stats.get_stat("speed") * phase_1_data.get("attack_speed_bonus", 0.3)
		stats.add_modifier("speed", "boss_phase_1_speed", speed_bonus)

		enrage_count = 1
		enraged.emit(enrage_count)

# ============================================================
# 信号回调
# ============================================================

func _on_stats_died() -> void:
	die()


func _on_health_changed(_current: float, _maximum: float) -> void:
	# 实时检查（behavior 相关逻辑在 _execute_behavior 中执行）
	pass

# ============================================================
# 灼烧 DOT
# ============================================================

## 灼烧 DOT 相关变量
var _burn_timer: Timer = null
var _burn_damage: float = 0.0
var _burn_ticks_remaining: int = 0
var _burn_tick_interval: float = 1.0

## 应用灼烧效果（不叠加，但刷新持续时间）
func apply_burn(dot_damage: float, dot_duration: float, tick_interval: float) -> void:
	if not is_active or not stats.is_alive():
		return

	_burn_damage = dot_damage
	_burn_tick_interval = tick_interval
	_burn_ticks_remaining = int(dot_duration / tick_interval)

	# 如果已有灼烧 Timer，刷新即可
	if _burn_timer != null and is_instance_valid(_burn_timer):
		_burn_timer.stop()
		_burn_timer.wait_time = tick_interval
		_burn_timer.start()
		return

	# 创建新 Timer
	_burn_timer = Timer.new()
	_burn_timer.wait_time = tick_interval
	_burn_timer.one_shot = false
	add_child(_burn_timer)
	_burn_timer.timeout.connect(_on_burn_tick)
	_burn_timer.start()


## 灼烧 tick 处理
func _on_burn_tick() -> void:
	if not is_active or not stats.is_alive():
		_stop_burn()
		return

	if _burn_ticks_remaining <= 0:
		_stop_burn()
		return

	# 造成真实伤害（无视防御）
	stats.take_damage(_burn_damage)

	# 简单的视觉提示：飘字
	if DamageSystem and DamageSystem.has_method("create_damage_number"):
		DamageSystem.create_damage_number(global_position, int(_burn_damage), false)

	_burn_ticks_remaining -= 1


## 停止灼烧效果
func _stop_burn() -> void:
	if _burn_timer != null and is_instance_valid(_burn_timer):
		_burn_timer.stop()
		_burn_timer.queue_free()
		_burn_timer = null
	_burn_ticks_remaining = 0

# ============================================================
# 数据加载
# ============================================================

## 从 enemies.json 加载当前 enemy_id 对应的数据
func _load_data_from_json() -> void:
	var file := FileAccess.open("res://data/enemies.json", FileAccess.READ)
	if file == null:
		push_warning("EnemyBase: 无法读取 enemies.json")
		return

	var json_text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var err: Error = json.parse(json_text)
	if err != OK:
		push_warning("EnemyBase: enemies.json 解析失败")
		return

	var data: Dictionary = json.data
	if not data.has("enemies"):
		return

	var enemies_array: Array = data["enemies"]
	for entry: Dictionary in enemies_array:
		if entry.get("id", "") == enemy_id:
			initialize(enemy_id, entry)
			return

	push_warning("EnemyBase: 未找到 enemy_id='%s' 的数据" % enemy_id)
