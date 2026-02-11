class_name GameManager
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

# ============================================================
# 属性
# ============================================================

## 游戏状态："menu" | "playing" | "paused" | "wave_clear" | "game_over"
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
var shared_hp: int = 60
var max_shared_hp: int = 60

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

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停时仍可接收信号

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
	game_state = "playing"
	shared_hp_changed.emit(shared_hp, max_shared_hp)


## 结束游戏
func end_game(victory: bool) -> void:
	game_state = "game_over"
	game_over.emit(victory)
