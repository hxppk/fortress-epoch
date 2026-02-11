extends Control
## 游戏内 HUD — 显示资源、血池、波次信息

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

	# 连接建筑快捷按钮信号
	if build_buttons:
		var arrow_btn := build_buttons.get_node_or_null("ArrowTowerBtn") as Button
		var mine_btn := build_buttons.get_node_or_null("GoldMineBtn") as Button
		var barracks_btn := build_buttons.get_node_or_null("BarracksBtn") as Button
		if arrow_btn:
			arrow_btn.pressed.connect(_on_build_arrow_tower)
		if mine_btn:
			mine_btn.pressed.connect(_on_build_gold_mine)
		if barracks_btn:
			barracks_btn.pressed.connect(_on_build_barracks)


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


func update_wave_info(wave_number: int, label: String) -> void:
	if wave_label:
		wave_label.text = "Wave %d: %s" % [wave_number, label]


func update_skill_cooldown(slot: int, remaining: float, total: float) -> void:
	var bar: ProgressBar = null
	if slot == 1:
		bar = skill1_bar
	elif slot == 2:
		bar = skill2_bar
	if bar:
		bar.max_value = total
		bar.value = total - remaining


func update_ultimate_charge(current: float, maximum: float) -> void:
	if ultimate_bar:
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
	var placement := _get_tower_placement()
	if placement and placement.has_method("start_placement"):
		placement.start_placement("arrow_tower")


func _on_build_gold_mine() -> void:
	var placement := _get_tower_placement()
	if placement and placement.has_method("start_placement"):
		placement.start_placement("gold_mine")


func _on_build_barracks() -> void:
	var placement := _get_tower_placement()
	if placement and placement.has_method("start_placement"):
		placement.start_placement("barracks")


func _get_tower_placement() -> Node:
	var session := get_tree().current_scene
	if session and session.has_node("TowerPlacement"):
		return session.get_node("TowerPlacement")
	return null
