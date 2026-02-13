class_name PhaseManager
extends Node
## PhaseManager -- 阶段管理器
## 管理游戏从引导到结局的完整流程，驱动阶段切换与倒计时。

# ============================================================
# 信号
# ============================================================

signal phase_changed(phase_name: String, phase_data: Dictionary)
signal transition_started(duration: float)
signal transition_tick(remaining: float)
signal transition_ended()
signal tutorial_message(text: String)
signal countdown_tick(seconds_remaining: int)

# ============================================================
# 阶段常量（字符串枚举）
# ============================================================
# "tutorial"        -- 引导阶段（stage_1_tutorial）
# "prepare"         -- 准备阶段（波间修整，可建造/升级）
# "defend"          -- 防守阶段（波次进行中）
# "wave_clear"      -- 波次清除（短暂 2 秒，显示奖励）
# "card_selection"  -- 卡牌选择
# "transition"      -- 阶段过渡（15 秒倒计时，选择出征目标）
# "expedition"      -- 出征中（英雄自动战斗副本，主画面继续运营）
# "boss"            -- BOSS 防守波
# "victory"         -- 胜利
# "defeat"          -- 失败

# ============================================================
# 属性
# ============================================================

## 当前阶段名称
var current_phase: String = ""

## 当前阶段索引：0=tutorial, 1=stage_2, ...
var current_stage_index: int = 0

## 阶段 ID 列表
var stages: Array = ["stage_1_tutorial", "stage_2"]

## 过渡倒计时剩余秒数
var transition_remaining: float = 0.0

## 是否正在过渡倒计时
var is_transitioning: bool = false

## WaveSpawner 引用（由外部传入）
var _wave_spawner: WaveSpawner = null

## 缓存最近一次 wave_clear 的奖励数据
var _last_rewards: Dictionary = {}

## 缓存最近完成的 wave_index
var _last_wave_index: int = -1

## 标记城镇是否在本次 wave_clear 期间升级（由外部设置）
var pending_card_selection: bool = false

## 缓存当前阶段的波次数据（用于 tutorial_text 等）
var _current_stage_waves: Array = []

# ============================================================
# 初始化
# ============================================================

## 初始化，传入 WaveSpawner 引用
func initialize(wave_spawner: WaveSpawner) -> void:
	_wave_spawner = wave_spawner

# ============================================================
# 游戏流程入口
# ============================================================

## 开始游戏流程（从引导阶段开始）
func start_game_flow() -> void:
	current_stage_index = 0
	enter_phase("tutorial")

# ============================================================
# 阶段切换核心
# ============================================================

## 进入指定阶段
func enter_phase(phase_name: String, data: Dictionary = {}) -> void:
	var prev_phase: String = current_phase
	current_phase = phase_name
	print("[PhaseManager] %s → %s" % [prev_phase if prev_phase != "" else "(init)", phase_name])
	phase_changed.emit(phase_name, data)

	match phase_name:
		"tutorial":
			_handle_tutorial(data)
		"prepare":
			_handle_prepare(data)
		"defend":
			_handle_defend(data)
		"wave_clear":
			_handle_wave_clear(data)
		"card_selection":
			_handle_card_selection(data)
		"transition":
			_handle_transition(data)
		"expedition":
			_handle_expedition(data)
		"boss":
			_handle_boss(data)
		"victory":
			_handle_victory(data)
		"defeat":
			_handle_defeat(data)
		_:
			push_warning("PhaseManager: 未知阶段 '%s'" % phase_name)

# ============================================================
# 各阶段处理
# ============================================================

## 引导阶段处理
func _handle_tutorial(_data: Dictionary) -> void:
	if _wave_spawner == null:
		push_warning("PhaseManager: WaveSpawner 未初始化")
		return

	var stage_id: String = stages[0]  # stage_1_tutorial
	_wave_spawner.load_stage(stage_id)

	# 缓存波次数据
	_current_stage_waves = _wave_spawner.current_stage_data.get("waves", [])

	# 1-1 波前发送引导消息
	if _current_stage_waves.size() > 0:
		var first_wave: Dictionary = _current_stage_waves[0]
		var text: String = first_wave.get("tutorial_text", "点击屏幕移动英雄，消灭所有史莱姆！")
		tutorial_message.emit(text)

	# 设置游戏状态为 playing
	var gm: Node = _get_game_manager()
	if gm:
		gm.game_state = "playing"

	# 延迟 1 秒后开始第一波
	await get_tree().create_timer(1.0).timeout
	_wave_spawner.start_next_wave()


## 准备阶段处理
func _handle_prepare(_data: Dictionary) -> void:
	var gm: Node = _get_game_manager()
	if gm:
		gm.game_state = "playing"

	# 前 7 秒静默准备
	await get_tree().create_timer(7.0).timeout

	# 最后 3 秒倒计时: 3, 2, 1
	for i in range(3, 0, -1):
		countdown_tick.emit(i)
		await get_tree().create_timer(1.0).timeout

	countdown_tick.emit(0)  # 隐藏倒计时
	enter_phase("defend")


## 防守阶段处理
func _handle_defend(_data: Dictionary) -> void:
	# 检查即将开始的波次是否是 BOSS 波，如果是则切换到 boss 阶段
	if _is_next_wave_boss():
		enter_phase("boss")
		return

	var gm: Node = _get_game_manager()
	if gm:
		gm.game_state = "playing"

	# 通知 WaveSpawner 开始下一波
	if _wave_spawner:
		_wave_spawner.start_next_wave()


## 波次清除处理
func _handle_wave_clear(data: Dictionary) -> void:
	var gm: Node = _get_game_manager()
	if gm:
		gm.game_state = "wave_clear"

	# 2 秒奖励展示
	await get_tree().create_timer(2.0).timeout

	# NEW: Check if expedition NPCs exist → enter attack mode
	# The expedition_battle node checks and game_session handles the start
	if _has_expedition_npcs():
		enter_phase("expedition", data)
		return

	# Continue normal flow
	_post_wave_clear_routing(data)


## 卡牌选择处理
func _handle_card_selection(_data: Dictionary) -> void:
	var gm: Node = _get_game_manager()
	if gm:
		gm.game_state = "card_selection"
	# 等待外部 UI 发信号后调用 on_card_selection_done()


## 阶段过渡处理（15 秒倒计时）
func _handle_transition(_data: Dictionary) -> void:
	var gm: Node = _get_game_manager()
	if gm:
		gm.game_state = "transition"

	start_transition(15.0)


## 出征处理
func _handle_expedition(_data: Dictionary) -> void:
	var gm: Node = _get_game_manager()
	if gm:
		gm.game_state = "expedition"
	# Actual battle managed by game_session via ExpeditionBattle


## BOSS 防守波处理
func _handle_boss(_data: Dictionary) -> void:
	var gm: Node = _get_game_manager()
	if gm:
		gm.game_state = "boss"

	# 通知 WaveSpawner 开始 BOSS 波
	if _wave_spawner:
		_wave_spawner.start_next_wave()


## 胜利处理
func _handle_victory(_data: Dictionary) -> void:
	print("[PhaseManager] 游戏胜利 — 触发结算")
	var gm: Node = _get_game_manager()
	if gm:
		gm.end_game(true)


## 失败处理
func _handle_defeat(_data: Dictionary) -> void:
	print("[PhaseManager] 游戏失败 — 触发结算")
	var gm: Node = _get_game_manager()
	if gm:
		gm.end_game(false)

# ============================================================
# 波次回调（由 game_session 连接 WaveSpawner 信号后调用）
# ============================================================

## 当前波次结束时调用
func on_wave_completed(wave_index: int, rewards: Dictionary) -> void:
	_last_wave_index = wave_index
	_last_rewards = rewards

	# 如果在引导阶段，发送对应的 tutorial_text
	if current_phase == "tutorial" or current_phase == "defend":
		if wave_index < _current_stage_waves.size():
			var wave_data: Dictionary = _current_stage_waves[wave_index]
			var text: String = wave_data.get("tutorial_text", "")
			if text != "":
				tutorial_message.emit(text)

	# 进入波次清除阶段
	enter_phase("wave_clear", {"wave_index": wave_index, "rewards": rewards})


## 当前阶段所有波次结束时调用
func on_all_waves_completed(stage_id: String) -> void:
	# 此信号可能在 wave_clear 之前或之后触发
	# 实际逻辑由 _handle_wave_clear 中的 is_all_waves_complete() 检查驱动
	# 这里作为备用入口
	if current_phase != "wave_clear":
		_on_stage_completed()

# ============================================================
# 阶段完成后的路由逻辑
# ============================================================

## 当前阶段全部波次完成后，决定下一步
func _on_stage_completed() -> void:
	var current_stage_id: String = stages[current_stage_index] if current_stage_index < stages.size() else ""

	# 如果是引导阶段完成，直接进入下一阶段的 prepare
	if current_stage_id == "stage_1_tutorial":
		_advance_to_next_stage()
		return

	# 检查下一阶段是否存在
	if current_stage_index + 1 < stages.size():
		# 还有下一阶段 → 直接推进
		_advance_to_next_stage()
	else:
		# 已是最后阶段 → 胜利
		enter_phase("victory")


## 推进到下一阶段
func _advance_to_next_stage() -> void:
	current_stage_index += 1

	if current_stage_index >= stages.size():
		enter_phase("victory")
		return

	var next_stage_id: String = stages[current_stage_index]

	# 加载新阶段数据
	if _wave_spawner:
		_wave_spawner.load_stage(next_stage_id)
		_current_stage_waves = _wave_spawner.current_stage_data.get("waves", [])

	# 检查新阶段的最后一波是否是 BOSS
	# （BOSS 波会在 defend 阶段的 wave_clear 中判断）
	enter_phase("prepare")

# ============================================================
# 过渡倒计时
# ============================================================

## 开始 15 秒过渡倒计时
func start_transition(duration: float = 15.0) -> void:
	transition_remaining = duration
	is_transitioning = true
	transition_started.emit(duration)


## 帧处理：过渡倒计时
func _process(delta: float) -> void:
	if is_transitioning:
		transition_remaining -= delta
		transition_tick.emit(transition_remaining)
		if transition_remaining <= 0.0:
			is_transitioning = false
			transition_ended.emit()
			# 自动进入出征阶段
			enter_phase("expedition")

# ============================================================
# 外部回调
# ============================================================

## 出征结束后调用
func on_expedition_completed() -> void:
	is_transitioning = false
	_post_wave_clear_routing()


## 卡牌选择完成后调用（由 game_session 在 card_selected 信号后调用）
func on_card_selection_done() -> void:
	# 检查是否所有波次已完成
	if _wave_spawner and _wave_spawner.is_all_waves_complete():
		_on_stage_completed()
		return

	# 否则继续下一波
	enter_phase("prepare")


## Post-wave-clear decision routing (also called after expedition completes)
func _post_wave_clear_routing(data: Dictionary = {}) -> void:
	if pending_card_selection:
		pending_card_selection = false
		enter_phase("card_selection", data)
		return

	if _wave_spawner and _wave_spawner.is_all_waves_complete():
		_on_stage_completed()
		return

	enter_phase("prepare")


## Check if expedition NPCs exist in the heroes group
func _has_expedition_npcs() -> bool:
	var heroes: Array = get_tree().get_nodes_in_group("heroes")
	for hero: Node in heroes:
		if hero is NPCUnit:
			return true
	return false


## 检查即将开始的波次是否是 BOSS 波
func _is_next_wave_boss() -> bool:
	if _wave_spawner == null:
		return false

	var wave_index: int = _wave_spawner.current_wave_index
	if wave_index < _current_stage_waves.size():
		var wave: Dictionary = _current_stage_waves[wave_index]
		return wave.get("label", "") == "BOSS"
	return false

# ============================================================
# 工具方法
# ============================================================

## 获取 GameManager 引用
func _get_game_manager() -> Node:
	return GameManager
