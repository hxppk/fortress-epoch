class_name ExpeditionManager
extends Node
## ExpeditionManager — 出征管理器
## 负责加载副本数据、编队、自动战斗数值模拟、文字播报、远程支援、奖励结算。

# ============================================================
# 信号
# ============================================================

signal expedition_started(expedition_id: String)
signal expedition_progress(message: String, progress: float)  # progress 0.0~1.0
signal expedition_completed(expedition_id: String, success: bool, rewards: Dictionary)
signal support_used(remaining: int)
signal expedition_selection_requested(available_expeditions: Array)

# ============================================================
# 常量
# ============================================================

const EXPEDITIONS_JSON_PATH: String = "res://data/expeditions.json"

# ============================================================
# 属性
# ============================================================

## 所有副本数据
var all_expeditions: Array = []

## 当前正在进行的出征
var active_expedition: Dictionary = {}
var is_active: bool = false

## 出征进度（0.0~1.0）
var expedition_progress_value: float = 0.0
var expedition_duration: float = 0.0
var expedition_elapsed: float = 0.0

## 播报进度（narration 的当前索引）
var narration_index: int = 0
var narration_timer: float = 0.0

## 远程支援
var support_remaining: int = 0
var support_bonus: float = 0.0

## 出征英雄属性（用于数值模拟）
var hero_power: float = 0.0

# ============================================================
# 生命周期
# ============================================================

func _process(delta: float) -> void:
	if not is_active:
		return

	expedition_elapsed += delta
	expedition_progress_value = clampf(expedition_elapsed / expedition_duration, 0.0, 1.0)

	# 播报叙事文字
	var narrations: Array = active_expedition.get("narration", [])
	if narrations.size() > 0:
		# 按进度均匀分配播报时间点
		var interval: float = expedition_duration / float(narrations.size())
		narration_timer += delta
		if narration_timer >= interval and narration_index < narrations.size():
			var msg: String = narrations[narration_index]
			expedition_progress.emit(msg, expedition_progress_value)
			narration_index += 1
			narration_timer -= interval

	# 出征结束
	if expedition_elapsed >= expedition_duration:
		_complete_expedition()

# ============================================================
# 核心方法
# ============================================================

## 初始化，加载 expeditions.json
func initialize() -> void:
	all_expeditions = _load_expeditions()


## 获取可用副本列表（返回 Array of Dictionary）
func get_available_expeditions() -> Array:
	return all_expeditions


## 请求出征选择界面
func request_expedition_selection() -> void:
	expedition_selection_requested.emit(all_expeditions)


## 开始出征
## hero_stats: { "attack": int, "defense": int, "hp": int, "speed": int } — 出征英雄的属性快照
func start_expedition(expedition_id: String, hero_stats: Dictionary) -> void:
	# 找到副本数据
	for exp_data in all_expeditions:
		if exp_data.get("id", "") == expedition_id:
			active_expedition = exp_data
			break

	if active_expedition.is_empty():
		push_warning("[ExpeditionManager] 未找到副本: %s" % expedition_id)
		return

	is_active = true
	expedition_elapsed = 0.0
	expedition_duration = float(active_expedition.get("duration", 60))
	expedition_progress_value = 0.0
	narration_index = 0
	narration_timer = 0.0

	# 计算英雄战力
	hero_power = _calculate_hero_power(hero_stats)

	# 初始化远程支援
	var support_config: Dictionary = active_expedition.get("support", {})
	support_remaining = int(support_config.get("max_chances", 2))
	support_bonus = 0.0

	expedition_started.emit(expedition_id)


## 使用远程支援（花费金币提升成功率）
func use_support() -> bool:
	if support_remaining <= 0:
		return false

	var support_config: Dictionary = active_expedition.get("support", {})
	var cost: Dictionary = support_config.get("cost_per_support", {})

	# 检查并扣除金币
	var gold_cost: int = int(cost.get("gold", 30))
	if not GameManager.spend_resource("gold", gold_cost):
		return false

	support_remaining -= 1
	support_bonus += float(support_config.get("success_rate_bonus", 0.15))
	support_used.emit(support_remaining)

	expedition_progress.emit("远程支援已发送！成功率提升！", expedition_progress_value)
	return true


## 跳过出征（直接结算）
func skip_expedition() -> void:
	if is_active:
		_complete_expedition()

# ============================================================
# 内部方法
# ============================================================

## 出征结算
func _complete_expedition() -> void:
	is_active = false

	# 计算成功率
	var base_rate: float = float(active_expedition.get("base_success_rate", 0.5))
	var recommended: float = float(active_expedition.get("recommended_power", 50))

	# 英雄战力影响：power / recommended 比值调整成功率
	var power_ratio: float = hero_power / maxf(recommended, 1.0)
	var power_modifier: float = clampf((power_ratio - 1.0) * 0.3, -0.2, 0.2)

	var final_rate: float = clampf(base_rate + power_modifier + support_bonus, 0.05, 0.95)
	var success: bool = randf() < final_rate

	# 计算奖励
	var rewards_config: Dictionary = active_expedition.get("rewards", {})
	var result_config: Dictionary = rewards_config.get("success" if success else "failure", {})
	var rewards: Dictionary = _roll_rewards(result_config)

	# 发放奖励
	for resource_type: String in rewards:
		if resource_type != "bonus_card":
			GameManager.add_resource(resource_type, int(rewards[resource_type]))

	var expedition_id: String = active_expedition.get("id", "")
	expedition_completed.emit(expedition_id, success, rewards)
	active_expedition = {}

# ============================================================
# 辅助方法
# ============================================================

## 计算英雄战力（简化公式）
func _calculate_hero_power(stats: Dictionary) -> float:
	var atk: float = float(stats.get("attack", 10))
	var def: float = float(stats.get("defense", 5))
	var hp: float = float(stats.get("hp", 100))
	var spd: float = float(stats.get("speed", 100))
	return atk * 2.0 + def * 1.5 + hp * 0.5 + spd * 0.3


## 根据奖励配置掷骰（范围值取随机）
func _roll_rewards(config: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in config:
		var val = config[key]
		if val is Array and val.size() == 2:
			result[key] = randi_range(int(val[0]), int(val[1]))
		elif val is float:
			# bonus_card_chance 等概率值，转为是否获得
			if key.ends_with("_chance"):
				result["bonus_card"] = randf() < float(val)
			else:
				result[key] = int(val)
		else:
			result[key] = val
	return result


## 加载出征数据
func _load_expeditions() -> Array:
	if not FileAccess.file_exists(EXPEDITIONS_JSON_PATH):
		push_error("[ExpeditionManager] expeditions.json 不存在")
		return []
	var file: FileAccess = FileAccess.open(EXPEDITIONS_JSON_PATH, FileAccess.READ)
	var json_text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(json_text) != OK:
		push_error("[ExpeditionManager] JSON 解析失败")
		return []
	return json.data.get("expeditions", [])
