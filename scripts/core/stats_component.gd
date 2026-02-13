class_name StatsComponent
extends Node
## StatsComponent — 实体属性组件
## 挂载到英雄 / 敌人 / 建筑节点下，统一管理 HP、ATK、DEF 等数值。
## 支持基础属性 + 修改器叠加。

# ============================================================
# 信号
# ============================================================

signal health_changed(current_hp: float, max_hp: float)
signal died()
signal stat_modified(stat_name: String, new_value: float)

# ============================================================
# 属性
# ============================================================

## 基础属性（从 JSON / Dictionary 加载）
var base_stats: Dictionary = {}

## 修改器 { stat_name: [{ "source": String, "value": float }] }
var modifiers: Dictionary = {}

## 当前与最大生命值
var current_hp: float = 0.0
var max_hp: float = 0.0

# ============================================================
# 初始化
# ============================================================

## 用数据字典初始化属性。
## data 示例：{ "hp": 100, "atk": 20, "def": 5, "speed": 80, "crit_rate": 0.1 }
func initialize(data: Dictionary) -> void:
	base_stats = data.duplicate(true)
	modifiers.clear()

	# 初始化生命值
	max_hp = get_stat("hp")
	current_hp = max_hp

	health_changed.emit(current_hp, max_hp)

# ============================================================
# 属性查询
# ============================================================

## 获取最终属性值 = base + sum(modifiers)
func get_stat(stat_name: String) -> float:
	var base_value: float = 0.0
	if base_stats.has(stat_name):
		base_value = float(base_stats[stat_name])

	var modifier_sum: float = 0.0
	if modifiers.has(stat_name):
		for mod: Dictionary in modifiers[stat_name]:
			modifier_sum += mod["value"]

	return base_value + modifier_sum

# ============================================================
# 修改器操作
# ============================================================

## 添加修改器
func add_modifier(stat_name: String, source: String, value: float) -> void:
	if not modifiers.has(stat_name):
		modifiers[stat_name] = []
	modifiers[stat_name].append({ "source": source, "value": value })

	var new_value := get_stat(stat_name)
	stat_modified.emit(stat_name, new_value)

	# 如果修改了 hp 上限，同步更新
	if stat_name == "hp":
		max_hp = new_value
		current_hp = minf(current_hp, max_hp)
		health_changed.emit(current_hp, max_hp)


## 移除指定来源的修改器
func remove_modifier(stat_name: String, source: String) -> void:
	if not modifiers.has(stat_name):
		return

	var list: Array = modifiers[stat_name]
	for i in range(list.size() - 1, -1, -1):
		if list[i]["source"] == source:
			list.remove_at(i)

	var new_value := get_stat(stat_name)
	stat_modified.emit(stat_name, new_value)

	if stat_name == "hp":
		max_hp = new_value
		current_hp = minf(current_hp, max_hp)
		health_changed.emit(current_hp, max_hp)

# ============================================================
# 生命值操作
# ============================================================

## 受到伤害，返回实际伤害值
func take_damage(amount: float) -> float:
	if current_hp <= 0.0:
		return 0.0

	var actual_damage: float = minf(amount, current_hp)
	current_hp -= actual_damage

	# 先将 HP 钳位到 0，再统一 emit，避免监听者收到负值
	var is_dead: bool = current_hp <= 0.0
	if is_dead:
		current_hp = 0.0

	health_changed.emit(current_hp, max_hp)

	if is_dead:
		died.emit()

	return actual_damage


## 治疗
func heal(amount: float) -> void:
	if current_hp <= 0.0:
		return  # 已死亡不可治疗

	current_hp = minf(current_hp + amount, max_hp)
	health_changed.emit(current_hp, max_hp)


## 是否存活
func is_alive() -> bool:
	return current_hp > 0.0
