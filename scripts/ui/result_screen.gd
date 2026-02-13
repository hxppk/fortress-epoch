extends Control
## 胜利/失败结算屏幕 — 显示战斗结果、统计数据和操作按钮

signal restart_requested()
signal main_menu_requested()

@onready var dim_overlay: ColorRect = $DimOverlay
@onready var panel: PanelContainer = $CenterPanel
@onready var title_label: Label = $CenterPanel/VBox/TitleLabel
@onready var subtitle_label: Label = $CenterPanel/VBox/SubtitleLabel
@onready var stats_container: VBoxContainer = $CenterPanel/VBox/StatsContainer
@onready var restart_button: Button = $CenterPanel/VBox/ButtonsContainer/RestartButton
@onready var menu_button: Button = $CenterPanel/VBox/ButtonsContainer/MenuButton


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停时仍可交互
	restart_button.pressed.connect(func(): restart_requested.emit())
	menu_button.pressed.connect(func(): main_menu_requested.emit())


## 显示结算界面
## victory: 是否胜利
## stats: { "kill_count": int, "total_damage": float, "gold_earned": int, "crystal_earned": int, "waves_survived": int, "town_level": int }
func show_result(victory: bool, stats: Dictionary) -> void:
	# 设置标题
	if victory:
		title_label.text = "胜利！"
		title_label.add_theme_color_override("font_color", Color.GOLD)
		subtitle_label.text = "堡垒安然无恙，英雄凯旋归来！"
	else:
		title_label.text = "堡垒陷落"
		title_label.add_theme_color_override("font_color", Color.RED)
		subtitle_label.text = "黑暗笼罩了大地..."

	# 清除旧统计
	for child in stats_container.get_children():
		child.queue_free()

	# 填充统计数据
	_add_stat_row("击杀数", str(stats.get("kill_count", 0)))
	_add_stat_row("总伤害", "%d" % int(stats.get("total_damage", 0)))
	_add_stat_row("获得金币", str(stats.get("gold_earned", 0)))
	_add_stat_row("获得水晶", str(stats.get("crystal_earned", 0)))
	_add_stat_row("存活波次", str(stats.get("waves_survived", 0)))
	_add_stat_row("城镇等级", "Lv.%d" % int(stats.get("town_level", 0)))

	# 局外成长信息
	_add_meta_progression_rows()

	# 显示面板 + 入场动画
	visible = true
	dim_overlay.modulate = Color(1, 1, 1, 0)
	panel.modulate = Color(1, 1, 1, 0)
	panel.scale = Vector2(0.8, 0.8)
	panel.pivot_offset = panel.size / 2.0

	var tween := create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(dim_overlay, "modulate:a", 1.0, 0.3)
	tween.tween_property(panel, "modulate:a", 1.0, 0.4)
	tween.parallel().tween_property(panel, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK)

	# 暂停游戏
	get_tree().paused = true


## 添加一行统计数据
func _add_stat_row(label_text: String, value_text: String) -> void:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var name_label := Label.new()
	name_label.text = label_text + ":"
	name_label.custom_minimum_size = Vector2(120, 0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(name_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	hbox.add_child(spacer)

	var val_label := Label.new()
	val_label.text = value_text
	val_label.custom_minimum_size = Vector2(80, 0)
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	val_label.add_theme_color_override("font_color", Color.GOLD)
	hbox.add_child(val_label)

	stats_container.add_child(hbox)


## 显示局外成长结算行
func _add_meta_progression_rows() -> void:
	if not is_instance_valid(SaveManager):
		return

	var info: Dictionary = SaveManager.last_settle_info
	if info.is_empty():
		return

	# 分隔线
	var sep := HSeparator.new()
	stats_container.add_child(sep)

	# 获得经验
	var exp_gained: int = info.get("hero_exp_gained", 0)
	_add_stat_row("英雄经验", "+%d" % exp_gained)

	# 英雄等级
	var new_level: int = info.get("new_level", 1)
	_add_stat_row("英雄等级", "Lv.%d" % new_level)

	# 升级提示
	if info.get("leveled_up", false):
		var level_up_label := Label.new()
		level_up_label.text = "LEVEL UP!"
		level_up_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		level_up_label.add_theme_color_override("font_color", Color.GOLD)
		level_up_label.add_theme_font_size_override("font_size", 24)
		stats_container.add_child(level_up_label)

		# 闪烁动画
		var tween := create_tween().set_loops(3)
		tween.tween_property(level_up_label, "modulate:a", 0.3, 0.3)
		tween.tween_property(level_up_label, "modulate:a", 1.0, 0.3)


## 隐藏结算界面
func hide_result() -> void:
	visible = false
	get_tree().paused = false
