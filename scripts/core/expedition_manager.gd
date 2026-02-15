class_name ExpeditionManager
extends Node
## ExpeditionManager -- 出征管理器
## 负责加载副本数据、编队、三段式实战管理、远程支援（3种类型）、奖励结算。
## 每个远征副本包含3个阶段：小怪阶段 → 精英阶段 → 城堡/BOSS阶段。

# ============================================================
# 信号
# ============================================================

signal expedition_started(expedition_id: String)
signal expedition_phase_changed(phase_index: int, phase_name: String, description: String)
signal expedition_phase_completed(phase_index: int, phase_name: String)
signal expedition_completed(expedition_id: String, success: bool, rewards: Dictionary)
signal support_used(support_type: String, remaining: int)
signal expedition_selection_requested(available_expeditions: Array)
signal expedition_timer_tick(remaining: float, phase_index: int)

# ============================================================
# 常量
# ============================================================

const EXPEDITIONS_JSON_PATH: String = "res://data/expeditions.json"

# ============================================================
# 属性
# ============================================================

## 所有副本数据（从 JSON 加载）
var all_expeditions: Array = []

## 支援类型配置
var support_types_config: Dictionary = {}

## 当前正在进行的出征数据
var active_expedition: Dictionary = {}
var is_active: bool = false

## 三段式阶段管理
var current_phase_index: int = 0
var phase_timer: float = 0.0
var phase_time_limit: float = 0.0

## 远程支援状态
var support_remaining: int = 0
var support_available_types: Array = []

## 攻击力增益 buff 剩余时间
var _buff_remaining: float = 0.0
var _buff_active: bool = false

# ============================================================
# 生命周期
# ============================================================

func _process(delta: float) -> void:
	if not is_active:
		return

	# 更新攻击力增益 buff 计时器
	if _buff_active:
		_buff_remaining -= delta
		if _buff_remaining <= 0.0:
			_buff_active = false
			_remove_attack_buff()

	# 更新阶段计时器
	phase_timer -= delta
	expedition_timer_tick.emit(phase_timer, current_phase_index)

	if phase_timer <= 0.0:
		# 时间耗尽，当前阶段失败
		_fail_expedition("timeout")

# ============================================================
# 核心方法
# ============================================================

## 初始化，加载 expeditions.json
func initialize() -> void:
	var data: Dictionary = _load_expeditions_data()
	all_expeditions = data.get("expeditions", [])
	support_types_config = data.get("support_types", {})


## 获取可用副本列表
func get_available_expeditions() -> Array:
	return all_expeditions


## 请求出征选择界面
func request_expedition_selection() -> void:
	expedition_selection_requested.emit(all_expeditions)


## 开始出征（三段式实战）
func start_expedition(expedition_id: String) -> void:
	# 找到副本数据
	active_expedition = {}
	for exp_data: Dictionary in all_expeditions:
		if exp_data.get("id", "") == expedition_id:
			active_expedition = exp_data
			break

	if active_expedition.is_empty():
		push_warning("[ExpeditionManager] 未找到副本: %s" % expedition_id)
		return

	is_active = true
	current_phase_index = 0
	_buff_active = false
	_buff_remaining = 0.0

	# 初始化远程支援
	var support_config: Dictionary = active_expedition.get("support", {})
	support_remaining = int(support_config.get("max_chances", 2))
	support_available_types = support_config.get("types", ["bombard", "heal", "buff"])

	expedition_started.emit(expedition_id)

	# 开始第一阶段
	_start_phase(0)


## 使用远程支援（指定类型）
func use_support(support_type: String) -> bool:
	if support_remaining <= 0:
		return false

	if support_type not in support_available_types:
		push_warning("[ExpeditionManager] 不可用的支援类型: %s" % support_type)
		return false

	var support_config: Dictionary = active_expedition.get("support", {})
	var cost: Dictionary = support_config.get("cost_per_support", {})
	var gold_cost: int = int(cost.get("gold", 30))

	if not GameManager.spend_resource("gold", gold_cost):
		return false

	support_remaining -= 1

	# 根据类型执行支援效果
	var type_config: Dictionary = support_types_config.get(support_type, {})
	_apply_support_effect(support_type, type_config)

	support_used.emit(support_type, support_remaining)
	return true


## 通知当前阶段所有敌人已清除（由 ExpeditionBattle 调用）
func on_phase_enemies_cleared() -> void:
	if not is_active:
		return
	_complete_current_phase()


## 通知城堡/BOSS 被摧毁（由 ExpeditionBattle 调用）
func on_castle_or_boss_destroyed() -> void:
	if not is_active:
		return
	_complete_current_phase()


## 通知英雄全部阵亡（由 ExpeditionBattle 调用）
func on_all_heroes_dead() -> void:
	if not is_active:
		return
	_fail_expedition("all_dead")


## 获取当前阶段数据
func get_current_phase_data() -> Dictionary:
	var phases: Array = active_expedition.get("phases", [])
	if current_phase_index < phases.size():
		return phases[current_phase_index]
	return {}


## 获取总阶段数
func get_total_phases() -> int:
	return active_expedition.get("phases", []).size()

# ============================================================
# 内部方法
# ============================================================

## 开始指定阶段
func _start_phase(phase_index: int) -> void:
	var phases: Array = active_expedition.get("phases", [])
	if phase_index >= phases.size():
		# 所有阶段完成 → 出征成功
		_succeed_expedition()
		return

	current_phase_index = phase_index
	var phase_data: Dictionary = phases[phase_index]

	phase_time_limit = float(phase_data.get("time_limit", 60))
	phase_timer = phase_time_limit

	var phase_name: String = phase_data.get("name", "阶段 %d" % (phase_index + 1))
	var description: String = phase_data.get("description", "")

	print("[ExpeditionManager] 开始阶段 %d: %s" % [phase_index + 1, phase_name])
	expedition_phase_changed.emit(phase_index, phase_name, description)


## 完成当前阶段
func _complete_current_phase() -> void:
	var phases: Array = active_expedition.get("phases", [])
	if current_phase_index < phases.size():
		var phase_data: Dictionary = phases[current_phase_index]
		var phase_name: String = phase_data.get("name", "")
		expedition_phase_completed.emit(current_phase_index, phase_name)

	# 推进到下一阶段
	_start_phase(current_phase_index + 1)


## 出征成功
func _succeed_expedition() -> void:
	is_active = false

	# 清除攻击力 buff
	if _buff_active:
		_buff_active = false
		_remove_attack_buff()

	# 计算奖励
	var rewards_config: Dictionary = active_expedition.get("rewards", {})
	var success_config: Dictionary = rewards_config.get("success", {})
	var rewards: Dictionary = _roll_rewards(success_config)

	# 发放奖励
	_distribute_rewards(rewards)

	var expedition_id: String = active_expedition.get("id", "")
	expedition_completed.emit(expedition_id, true, rewards)
	active_expedition = {}


## 出征失败
func _fail_expedition(reason: String) -> void:
	is_active = false
	print("[ExpeditionManager] 出征失败: %s" % reason)

	# 清除攻击力 buff
	if _buff_active:
		_buff_active = false
		_remove_attack_buff()

	# 计算失败奖励
	var rewards_config: Dictionary = active_expedition.get("rewards", {})
	var failure_config: Dictionary = rewards_config.get("failure", {})
	var rewards: Dictionary = _roll_rewards(failure_config)

	# 发放失败奖励
	_distribute_rewards(rewards)

	var expedition_id: String = active_expedition.get("id", "")
	expedition_completed.emit(expedition_id, false, rewards)
	active_expedition = {}


## 应用支援效果
func _apply_support_effect(support_type: String, config: Dictionary) -> void:
	match support_type:
		"bombard":
			# 范围伤害：对所有远征中的敌人造成伤害
			var damage: float = float(config.get("damage", 150))
			var enemies: Array = get_tree().get_nodes_in_group("expedition_enemies")
			for enemy: Node in enemies:
				if is_instance_valid(enemy) and enemy.has_method("take_damage"):
					enemy.take_damage(damage)
			print("[ExpeditionManager] 轰炸支援: 对 %d 个敌人造成 %d 伤害" % [enemies.size(), int(damage)])

		"heal":
			# 治疗：回复所有远征英雄 30% HP
			var heal_percent: float = float(config.get("heal_percent", 0.30))
			var heroes: Array = get_tree().get_nodes_in_group("expedition_heroes")
			for hero: Node in heroes:
				if is_instance_valid(hero) and hero.has_method("heal"):
					var max_hp: float = hero.stats.max_hp if "stats" in hero else 100.0
					hero.heal(max_hp * heal_percent)
			print("[ExpeditionManager] 治疗支援: 回复全队 %d%% HP" % int(heal_percent * 100))

		"buff":
			# 增益：全队攻击力 +20%，持续 30 秒
			var attack_bonus: float = float(config.get("attack_bonus_percent", 0.20))
			var duration: float = float(config.get("duration", 30.0))
			_apply_attack_buff(attack_bonus)
			_buff_remaining = duration
			_buff_active = true
			print("[ExpeditionManager] 增益支援: 全队 ATK +%d%% 持续 %ds" % [int(attack_bonus * 100), int(duration)])


## 应用攻击力增益 buff
func _apply_attack_buff(bonus_percent: float) -> void:
	var heroes: Array = get_tree().get_nodes_in_group("expedition_heroes")
	for hero: Node in heroes:
		if is_instance_valid(hero) and "stats" in hero:
			var base_attack: float = hero.stats.get_stat("attack")
			var buff_value: float = base_attack * bonus_percent
			hero.stats.add_modifier("attack", "expedition_buff", buff_value)


## 移除攻击力增益 buff
func _remove_attack_buff() -> void:
	var heroes: Array = get_tree().get_nodes_in_group("expedition_heroes")
	for hero: Node in heroes:
		if is_instance_valid(hero) and "stats" in hero:
			hero.stats.remove_modifier("attack", "expedition_buff")


## 发放奖励
func _distribute_rewards(rewards: Dictionary) -> void:
	for resource_type: String in rewards:
		if resource_type == "bonus_card" or resource_type.ends_with("_chance"):
			continue
		var amount = rewards[resource_type]
		if amount is bool:
			continue
		if resource_type == "exp" and GameManager.has_method("add_exp"):
			GameManager.add_exp(int(amount))
		elif GameManager.has_method("add_resource"):
			GameManager.add_resource(resource_type, int(amount))


## 根据奖励配置掷骰
func _roll_rewards(config: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in config:
		var val = config[key]
		if val is Array and val.size() == 2:
			result[key] = randi_range(int(val[0]), int(val[1]))
		elif val is float:
			if key.ends_with("_chance"):
				result["bonus_card"] = randf() < float(val)
			else:
				result[key] = int(val)
		else:
			result[key] = val
	return result


## 加载出征数据
func _load_expeditions_data() -> Dictionary:
	if not FileAccess.file_exists(EXPEDITIONS_JSON_PATH):
		push_error("[ExpeditionManager] expeditions.json 不存在")
		return {}
	var file: FileAccess = FileAccess.open(EXPEDITIONS_JSON_PATH, FileAccess.READ)
	var json_text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(json_text) != OK:
		push_error("[ExpeditionManager] JSON 解析失败")
		return {}
	return json.data
