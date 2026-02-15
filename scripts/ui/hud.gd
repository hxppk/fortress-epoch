extends Control
## 游戏内 HUD — 三级信息层级设计
## Tier 1 (始终可见): 共享 HP、当前波次
## Tier 2 (常驻低调): 资源栏、技能冷却、城镇等级
## Tier 3 (动态显隐): 击杀数、经验进度、连杀提示

@onready var gold_label: Label = $TopBar/GoldLabel
@onready var crystal_label: Label = $TopBar/CrystalLabel
@onready var hp_bar: ProgressBar = $TopBar/HPBar
@onready var hp_label: Label = $TopBar/HPBar/HPLabel
@onready var wave_label: Label = $TopBar/WaveLabel
@onready var exp_label: Label = $TopBar/ExpLabel
@onready var town_level_label: Label = $TopBar/TownLevelLabel
@onready var kill_label: Label = $TopBar/KillLabel
@onready var skill1_bar: ProgressBar = $BottomBar/Skill1Bar
@onready var skill2_bar: ProgressBar = $BottomBar/Skill2Bar
@onready var ultimate_bar: ProgressBar = $BottomBar/UltimateBar
var build_buttons: HBoxContainer = null
var countdown_label: Label = null
var castle_hp_label: Label = null

# 三级信息层级
## Tier 3 动态显隐（战斗激烈时自动隐藏）
var _tier3_nodes: Array[Control] = []
var _tier3_visible: bool = true
var _tier3_auto_hide_timer: float = 0.0
const TIER3_AUTO_HIDE_DELAY: float = 5.0  # 5秒无击杀后显示 tier3

# 低血量警告
var _low_hp_warning_active: bool = false
var _low_hp_pulse_timer: float = 0.0
var _low_hp_overlay: ColorRect = null
var _low_hp_canvas: CanvasLayer = null

# 阶段/波次追踪
var _current_stage_index: int = 0
var _total_stages: int = 3

# 波次清除反馈
var _wave_clear_label: Label = null


func _ready() -> void:
	build_buttons = get_node_or_null("BottomBar/BuildButtons") as HBoxContainer
	GameManager.resource_changed.connect(_on_resource_changed)
	GameManager.shared_hp_changed.connect(_on_hp_changed)
	GameManager.game_over.connect(_on_game_over)

	# 安全连接新增信号
	if GameManager.has_signal("exp_changed"):
		GameManager.exp_changed.connect(_on_exp_changed)
	if GameManager.has_signal("town_level_up"):
		GameManager.town_level_up.connect(_on_town_level_up)
	if GameManager.has_signal("kill_recorded"):
		GameManager.kill_recorded.connect(_on_kill_recorded)

	# 初始化显示
	_on_resource_changed("gold", GameManager.resources.get("gold", 0))
	_on_resource_changed("crystal", GameManager.resources.get("crystal", 0))
	_on_hp_changed(GameManager.shared_hp, GameManager.max_shared_hp)

	# 初始化经验、城镇等级、击杀计数
	if exp_label:
		exp_label.text = "EXP: 0/20"
	if town_level_label:
		town_level_label.text = "Town Lv.0"
	if kill_label:
		kill_label.text = "Kills: 0"

	# 技能进度条默认隐藏（等技能系统初始化后由 update_skill_cooldown 显示）
	if skill1_bar:
		skill1_bar.visible = false
	if skill2_bar:
		skill2_bar.visible = false
	if ultimate_bar:
		ultimate_bar.visible = false

	# 连接建筑快捷按钮信号
	if build_buttons:
		var arrow_btn := build_buttons.get_node_or_null("ArrowTowerBtn") as Button
		var mine_btn := build_buttons.get_node_or_null("GoldMineBtn") as Button
		var barracks_btn := build_buttons.get_node_or_null("BarracksBtn") as Button
		if arrow_btn:
			arrow_btn.pressed.connect(_on_build_arrow_tower)
			arrow_btn.text = "箭塔(50金)[1]"
		if mine_btn:
			mine_btn.pressed.connect(_on_build_gold_mine)
			mine_btn.text = "金矿(50金)[2]"
		if barracks_btn:
			barracks_btn.pressed.connect(_on_build_barracks)
			barracks_btn.text = "兵营(30经验)[3]"

	# 创建倒计时标签（HUD 中央偏上）
	countdown_label = Label.new()
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_size_override("font_size", 64)
	countdown_label.add_theme_color_override("font_color", Color.YELLOW)
	countdown_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	countdown_label.add_theme_constant_override("shadow_offset_x", 3)
	countdown_label.add_theme_constant_override("shadow_offset_y", 3)
	countdown_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	countdown_label.offset_top = 38.0
	countdown_label.offset_bottom = 90.0
	countdown_label.offset_left = -40.0
	countdown_label.offset_right = 40.0
	countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown_label.visible = false
	add_child(countdown_label)

	# 创建城堡生命标签（左下角）
	castle_hp_label = Label.new()
	castle_hp_label.add_theme_font_size_override("font_size", 20)
	castle_hp_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	castle_hp_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	castle_hp_label.add_theme_constant_override("shadow_offset_x", 1)
	castle_hp_label.add_theme_constant_override("shadow_offset_y", 1)
	castle_hp_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	castle_hp_label.offset_left = 8.0
	castle_hp_label.offset_top = -60.0
	castle_hp_label.offset_right = 200.0
	castle_hp_label.offset_bottom = -42.0
	castle_hp_label.text = "堡垒生命: %d" % GameManager.shared_hp
	add_child(castle_hp_label)

	# 注册 Tier 3 节点（战斗激烈时可隐藏）
	if exp_label:
		_tier3_nodes.append(exp_label)
	if kill_label:
		_tier3_nodes.append(kill_label)

	# 创建低血量警告遮罩
	_create_low_hp_overlay()

	# 创建波次清除标签
	_wave_clear_label = Label.new()
	_wave_clear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_clear_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wave_clear_label.add_theme_font_size_override("font_size", 36)
	_wave_clear_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	_wave_clear_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_wave_clear_label.add_theme_constant_override("shadow_offset_x", 2)
	_wave_clear_label.add_theme_constant_override("shadow_offset_y", 2)
	_wave_clear_label.set_anchors_preset(Control.PRESET_CENTER)
	_wave_clear_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_wave_clear_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_wave_clear_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_clear_label.visible = false
	add_child(_wave_clear_label)


func _process(delta: float) -> void:
	# 低血量脉冲效果
	if _low_hp_warning_active and _low_hp_overlay:
		_low_hp_pulse_timer += delta * 3.14  # ~ 心跳节奏
		var alpha: float = 0.08 + 0.07 * sin(_low_hp_pulse_timer)
		_low_hp_overlay.color = Color(1.0, 0.0, 0.0, alpha)

	# Tier 3 自动隐藏计时（战斗中隐藏杂项信息）
	if not _tier3_visible:
		_tier3_auto_hide_timer -= delta
		if _tier3_auto_hide_timer <= 0.0:
			_set_tier3_visible(true)


func _on_resource_changed(type: String, new_amount: int) -> void:
	match type:
		"gold":
			if gold_label:
				gold_label.text = "Gold: %d" % new_amount
		"crystal":
			if crystal_label:
				crystal_label.text = "Crystal: %d" % new_amount


func _on_hp_changed(current: int, maximum: int) -> void:
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current
	if hp_label:
		hp_label.text = "%d / %d" % [current, maximum]
	if castle_hp_label:
		castle_hp_label.text = "堡垒生命: %d" % current

	# 低血量警告（< 30%）
	var hp_ratio: float = float(current) / maxf(float(maximum), 1.0)
	if hp_ratio < 0.30 and not _low_hp_warning_active:
		_low_hp_warning_active = true
		_low_hp_pulse_timer = 0.0
		if _low_hp_overlay:
			_low_hp_overlay.visible = true
	elif hp_ratio >= 0.30 and _low_hp_warning_active:
		_low_hp_warning_active = false
		if _low_hp_overlay:
			_low_hp_overlay.visible = false

	# HP 条颜色变化：绿 -> 黄 -> 红
	if hp_bar:
		var bar_style := hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if bar_style == null:
			bar_style = StyleBoxFlat.new()
			hp_bar.add_theme_stylebox_override("fill", bar_style)
		if hp_ratio > 0.6:
			bar_style.bg_color = Color(0.2, 0.8, 0.2)  # 绿
		elif hp_ratio > 0.3:
			bar_style.bg_color = Color(0.9, 0.8, 0.2)  # 黄
		else:
			bar_style.bg_color = Color(0.9, 0.2, 0.2)  # 红


## 更新波次信息（阶段 + 波次格式）
func update_wave_info(wave_number: int, label: String) -> void:
	if wave_label:
		if _current_stage_index > 0:
			wave_label.text = "Stage %d - Wave %d: %s" % [_current_stage_index, wave_number, label]
		else:
			wave_label.text = "Wave %d: %s" % [wave_number, label]


## 设置当前阶段索引（由 GameSession/PhaseManager 调用）
func set_stage_info(stage_index: int, total_stages: int = 3) -> void:
	_current_stage_index = stage_index
	_total_stages = total_stages


## 显示波次清除反馈
func show_wave_clear() -> void:
	if _wave_clear_label == null:
		return
	_wave_clear_label.text = "Wave Clear!"
	_wave_clear_label.visible = true
	_wave_clear_label.modulate = Color.WHITE
	_wave_clear_label.scale = Vector2(0.5, 0.5)
	_wave_clear_label.pivot_offset = _wave_clear_label.size / 2.0

	var tween := create_tween()
	tween.tween_property(_wave_clear_label, "scale", Vector2(1.2, 1.2), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_wave_clear_label, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_interval(1.0)
	tween.tween_property(_wave_clear_label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void: _wave_clear_label.visible = false)


func update_skill_cooldown(slot: int, remaining: float, total: float) -> void:
	var bar: ProgressBar = null
	if slot == 1:
		bar = skill1_bar
	elif slot == 2:
		bar = skill2_bar
	if bar:
		if not bar.visible:
			bar.visible = true
		bar.max_value = total
		bar.value = total - remaining


func update_ultimate_charge(current: float, maximum: float) -> void:
	if ultimate_bar:
		if not ultimate_bar.visible:
			ultimate_bar.visible = true
		ultimate_bar.max_value = maximum
		ultimate_bar.value = current


func _on_game_over(victory: bool) -> void:
	var result_text := "Victory!" if victory else "Defeat..."
	print("[HUD] Game Over: %s" % result_text)


# ---- 经验值显示 ----
func _on_exp_changed(current_exp: int, next_threshold: int) -> void:
	if exp_label:
		exp_label.text = "EXP: %d/%d" % [current_exp, next_threshold]


# ---- 城镇等级 ----
func _on_town_level_up(new_level: int) -> void:
	if town_level_label:
		town_level_label.text = "Town Lv.%d" % new_level
	_show_level_up_notification(new_level)


# ---- 击杀计数 ----
func _on_kill_recorded(total_kills: int) -> void:
	if kill_label:
		kill_label.text = "Kills: %d" % total_kills
	# 击杀时暂时隐藏 tier3 杂项（战斗激烈中）
	_tier3_auto_hide_timer = TIER3_AUTO_HIDE_DELAY


# ---- 城镇升级通知（屏幕中央大字 Tween 淡出） ----
func _show_level_up_notification(level: int) -> void:
	var notification := Label.new()
	notification.text = "Town Level Up! Lv.%d" % level
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notification.add_theme_font_size_override("font_size", 36)
	notification.add_theme_color_override("font_color", Color.GOLD)
	notification.anchors_preset = Control.PRESET_CENTER
	notification.grow_horizontal = Control.GROW_DIRECTION_BOTH
	notification.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(notification)

	var tween := create_tween()
	tween.tween_property(notification, "modulate:a", 0.0, 1.5).set_delay(0.8)
	tween.tween_callback(notification.queue_free)


# ---- 建筑快捷按钮回调 ----
func _on_build_arrow_tower() -> void:
	if CombatFeedback and CombatFeedback.has_method("play_click_sound"):
		CombatFeedback.play_click_sound()
	var placement := _get_tower_placement()
	if placement and placement.has_method("start_placement"):
		placement.start_placement("arrow_tower")


func _on_build_gold_mine() -> void:
	if CombatFeedback and CombatFeedback.has_method("play_click_sound"):
		CombatFeedback.play_click_sound()
	var placement := _get_tower_placement()
	if placement and placement.has_method("start_placement"):
		placement.start_placement("gold_mine")


func _on_build_barracks() -> void:
	if CombatFeedback and CombatFeedback.has_method("play_click_sound"):
		CombatFeedback.play_click_sound()
	var placement := _get_tower_placement()
	if placement and placement.has_method("start_placement"):
		placement.start_placement("barracks")


func _get_tower_placement() -> Node:
	var session := get_tree().current_scene
	if session and session.has_node("TowerPlacement"):
		return session.get_node("TowerPlacement")
	return null


## 显示/隐藏建筑快捷按钮（出征时隐藏）
func set_build_buttons_visible(vis: bool) -> void:
	if build_buttons:
		build_buttons.visible = vis


## 显示/隐藏波次倒计时
func show_countdown(seconds: int) -> void:
	if countdown_label == null:
		return
	if seconds <= 0:
		countdown_label.visible = false
		countdown_label.text = ""
	else:
		countdown_label.text = str(seconds)
		countdown_label.visible = true


## 显示新手引导提示（居中大字，3 秒淡出）
func show_tutorial_tip(text: String) -> void:
	# 背景面板（不拦截鼠标事件）
	var tip_panel := PanelContainer.new()
	tip_panel.set_anchors_preset(Control.PRESET_CENTER)
	tip_panel.offset_left = -200.0
	tip_panel.offset_right = 200.0
	tip_panel.offset_top = -40.0
	tip_panel.offset_bottom = 40.0
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tip_panel)

	# 文字标签（不拦截鼠标事件）
	var tip_label := Label.new()
	tip_label.text = text
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tip_label.add_theme_font_size_override("font_size", 24)
	tip_label.add_theme_color_override("font_color", Color.WHITE)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.add_child(tip_label)

	# Tween 淡出动画
	var tween := create_tween()
	tween.tween_property(tip_panel, "modulate:a", 0.0, 2.0).set_delay(3.0)
	tween.tween_callback(tip_panel.queue_free)


# ============================================================
# 内部工具
# ============================================================

## 设置 Tier 3 信息可见性
func _set_tier3_visible(visible: bool) -> void:
	_tier3_visible = visible
	for node: Control in _tier3_nodes:
		if is_instance_valid(node):
			node.visible = visible


## 创建低血量红色脉冲遮罩
func _create_low_hp_overlay() -> void:
	_low_hp_canvas = CanvasLayer.new()
	_low_hp_canvas.layer = 80
	add_child(_low_hp_canvas)

	_low_hp_overlay = ColorRect.new()
	_low_hp_overlay.color = Color(1.0, 0.0, 0.0, 0.0)
	_low_hp_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_low_hp_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_low_hp_overlay.visible = false
	_low_hp_canvas.add_child(_low_hp_overlay)
