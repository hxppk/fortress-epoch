extends Node
## GameManager — 全局游戏状态管理（Autoload 单例）
## 管理游戏状态机、共享血池、资源、击杀/伤害统计。

# ============================================================
# 信号
# ============================================================

signal resource_changed(type: String, new_amount: int)
signal shared_hp_changed(current: int, maximum: int)
signal game_state_changed(new_state: String)
signal kill_recorded(total_kills: int)
signal last_stand_activated()
signal game_over(victory: bool)
signal exp_changed(current_exp: int, next_threshold: int)
signal town_level_up(new_level: int)

# ============================================================
# 属性
# ============================================================

## 游戏状态："menu" | "playing" | "paused" | "wave_clear" | "card_selection" | "transition" | "expedition" | "boss" | "game_over"
var game_state: String = "menu":
	set(value):
		if game_state != value:
			game_state = value
			game_state_changed.emit(game_state)

## 资源池
var resources: Dictionary = {
	"gold": 100,
	"crystal": 0,
	"badge": 0,
	"exp": 0,
}

## 共享血池
var shared_hp: int = 50
var max_shared_hp: int = 50

## 关卡 / 波次
var current_stage: int = 1
var current_wave: int = 0

## 玩家数量（本地双人预留）
var player_count: int = 1

## 统计
var kill_count: int = 0
var total_damage_dealt: float = 0.0

# 标记是否已经触发过 last_stand，避免重复发信号
var _last_stand_triggered: bool = false

## 城镇等级
var town_level: int = 0

## 升级所需累计经验阈值
var exp_thresholds: Array = [0, 20, 70, 170, 370, 600]

## 累计经验
var total_exp: int = 0

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停时仍可接收信号
	last_stand_activated.connect(activate_last_stand_buff)

# ============================================================
# 资源操作
# ============================================================

## 增加资源
func add_resource(type: String, amount: int) -> void:
	if not resources.has(type):
		resources[type] = 0
	resources[type] += amount
	resource_changed.emit(type, resources[type])


## 消耗资源，余额不足返回 false
func spend_resource(type: String, amount: int) -> bool:
	if not resources.has(type):
		return false
	if resources[type] < amount:
		return false
	resources[type] -= amount
	resource_changed.emit(type, resources[type])
	return true

# ============================================================
# 共享血池
# ============================================================

## 对共享血池造成伤害
func take_shared_damage(amount: int) -> void:
	shared_hp = maxi(shared_hp - amount, 0)
	shared_hp_changed.emit(shared_hp, max_shared_hp)

	# 检查 last_stand
	if check_last_stand() and not _last_stand_triggered:
		_last_stand_triggered = true
		last_stand_activated.emit()

	# 血量归零 -> 游戏失败
	if shared_hp <= 0:
		end_game(false)

# ============================================================
# 统计
# ============================================================

## 记录一次击杀
func record_kill() -> void:
	kill_count += 1

	# 击杀金币加成：每次击杀获得基础金币 + BuildingManager 的加成
	var base_kill_gold: int = 1
	var bonus_gold: int = get_kill_gold(base_kill_gold)
	if bonus_gold > 0:
		add_resource("gold", bonus_gold)

	kill_recorded.emit(kill_count)


## 累计伤害
func record_damage(amount: float) -> void:
	total_damage_dealt += amount


## 判断是否进入 "最后一搏" 阶段（血量 < 30%）
func check_last_stand() -> bool:
	return shared_hp < ceili(max_shared_hp * 0.3)

# ============================================================
# 游戏流程
# ============================================================

## 游戏开始时间（用于计算 play_time）
var _game_start_time: float = 0.0

## 当前使用的英雄 ID
var current_hero_id: String = "wolf_knight"

## 开始游戏 — 重置所有状态
func start_game() -> void:
	resources = {
		"gold": 100,
		"crystal": 0,
		"badge": 0,
		"exp": 0,
	}
	shared_hp = max_shared_hp
	current_wave = 0
	kill_count = 0
	total_damage_dealt = 0.0
	_last_stand_triggered = false
	town_level = 0
	total_exp = 0
	_game_start_time = Time.get_ticks_msec() / 1000.0
	game_state = "playing"
	shared_hp_changed.emit(shared_hp, max_shared_hp)

	# 读取局外加成（预留，当前加成为 0）
	_apply_meta_bonuses()


## 结束游戏
func end_game(victory: bool) -> void:
	game_state = "game_over"

	# 局内 → 局外结算
	_settle_to_meta(victory)

	game_over.emit(victory)


## 根据玩家数量初始化共享血池（读 waves.json 的 shared_hp_pool.by_player_count 配置）
func setup_shared_hp_by_players(player_count_val: int, hp_config: Dictionary) -> void:
	var key: String = str(player_count_val)
	if hp_config.has(key):
		var cfg: Dictionary = hp_config[key]
		max_shared_hp = int(cfg.get("initial_hp", 20))
		shared_hp = max_shared_hp
		shared_hp_changed.emit(shared_hp, max_shared_hp)


## 激活背水一战 buff -- 为所有英雄增加攻击力 +20%
func activate_last_stand_buff() -> void:
	var heroes: Array[Node] = get_tree().get_nodes_in_group("heroes")
	for hero: Node in heroes:
		if hero.has_node("StatsComponent"):
			var stats: StatsComponent = hero.get_node("StatsComponent")
			var base_attack: float = stats.get_stat("attack")
			var bonus: int = roundi(base_attack * 0.2)
			stats.add_modifier("attack", "last_stand_buff", float(bonus))

# ============================================================
# 经验 / 城镇等级
# ============================================================

## 添加经验，检查是否升级（含卡牌经验加成）
func add_exp(amount: int) -> void:
	var bonus_mult: float = 1.0
	if has_meta("resource_modifiers"):
		var mods: Dictionary = get_meta("resource_modifiers")
		bonus_mult += mods.get("exp_gain_bonus", 0.0)
	var final_amount: int = maxi(roundi(float(amount) * bonus_mult), 1)
	total_exp += final_amount
	_check_town_level_up()

	# 计算下一级阈值用于 UI 显示
	var next_threshold: int = _get_next_exp_threshold()
	exp_changed.emit(total_exp, next_threshold)


## 检查城镇等级提升
func _check_town_level_up() -> void:
	# 持续检查，支持一次性跨多级升级
	while true:
		var next_level: int = town_level + 1
		if next_level >= exp_thresholds.size():
			break  # 已达最高等级

		if total_exp >= exp_thresholds[next_level]:
			town_level = next_level
			town_level_up.emit(town_level)
		else:
			break


## 计算含加成的击杀金币（联动 BuildingManager + 卡牌资源加成）
func get_kill_gold(base_gold: int) -> int:
	var bonus: float = 0.0
	if BuildingManager and BuildingManager.has_method("get_kill_gold_bonus"):
		bonus = BuildingManager.get_kill_gold_bonus()

	# 卡牌系统的击杀金币加成
	if has_meta("resource_modifiers"):
		var mods: Dictionary = get_meta("resource_modifiers")
		bonus += mods.get("kill_gold_bonus", 0.0)

	var final_gold: float = float(base_gold) * (1.0 + bonus)

	# 卡牌系统的双倍掉落判定
	if has_meta("resource_modifiers"):
		var mods: Dictionary = get_meta("resource_modifiers")
		var double_chance: float = mods.get("double_loot_chance", 0.0)
		if double_chance > 0.0 and randf() < double_chance:
			final_gold *= 2.0

	return roundi(final_gold)


## 获取当前城镇等级
func get_town_level() -> int:
	return town_level


## 获取下一级经验阈值（内部辅助）
func _get_next_exp_threshold() -> int:
	var next_level: int = town_level + 1
	if next_level < exp_thresholds.size():
		return exp_thresholds[next_level]
	# 已满级，返回当前阈值
	return exp_thresholds[exp_thresholds.size() - 1]

# ============================================================
# 局外成长集成
# ============================================================

## 局内结算 → 存档
func _settle_to_meta(victory: bool) -> void:
	if not is_instance_valid(SaveManager):
		return

	var play_time: float = (Time.get_ticks_msec() / 1000.0) - _game_start_time
	var game_stats: Dictionary = {
		"kills": kill_count,
		"wave": current_wave,
		"play_time": play_time,
		"crystal": resources.get("crystal", 0),
		"badge": resources.get("badge", 0),
		"hero_id": current_hero_id,
	}
	SaveManager.settle_game(victory, game_stats)


## 读取局外加成并应用（预留接口，当前加成为 0）
func _apply_meta_bonuses() -> void:
	if not is_instance_valid(SaveManager):
		return

	var bonus: Dictionary = SaveManager.get_hero_bonus(current_hero_id)
	if bonus.is_empty():
		return

	# 预留：将在英雄生成后通过 StatsComponent 应用加成
	# 目前仅打印日志
	var atk_pct: float = bonus.get("attack_pct", 0.0)
	if atk_pct > 0.0:
		print("[GameManager] 局外加成 — attack:+%.0f%% hp:+%.0f%% def:+%.0f%%" % [
			atk_pct * 100, bonus.get("hp_pct", 0.0) * 100, bonus.get("defense_pct", 0.0) * 100
		])
