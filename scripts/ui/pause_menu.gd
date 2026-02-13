extends Control
## 暂停菜单 — ESC 暂停游戏，显示继续/重启/返回主菜单按钮

signal resume_requested()
signal restart_requested()
signal main_menu_requested()

var dim_overlay: ColorRect = null
var panel: PanelContainer = null
var title_label: Label = null
var resume_button: Button = null
var restart_button: Button = null
var menu_button: Button = null


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停时仍可交互
	_build_ui()


## 纯代码构建 UI
func _build_ui() -> void:
	# 半透明黑色背景遮罩
	dim_overlay = ColorRect.new()
	dim_overlay.color = Color(0, 0, 0, 0.7)
	dim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim_overlay)

	# 中央面板
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -120.0
	panel.offset_right = 120.0
	panel.offset_top = -120.0
	panel.offset_bottom = 120.0
	add_child(panel)

	# 垂直容器
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# 标题
	title_label = Label.new()
	title_label.text = "暂停"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", Color.GOLD)
	vbox.add_child(title_label)

	# 间距
	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer1)

	# 继续游戏按钮
	resume_button = Button.new()
	resume_button.text = "继续游戏"
	resume_button.custom_minimum_size = Vector2(180, 40)
	resume_button.pressed.connect(_on_resume_pressed)
	vbox.add_child(resume_button)

	# 重新开始按钮
	restart_button = Button.new()
	restart_button.text = "重新开始"
	restart_button.custom_minimum_size = Vector2(180, 40)
	restart_button.pressed.connect(_on_restart_pressed)
	vbox.add_child(restart_button)

	# 返回主菜单按钮
	menu_button = Button.new()
	menu_button.text = "返回主菜单"
	menu_button.custom_minimum_size = Vector2(180, 40)
	menu_button.pressed.connect(_on_menu_pressed)
	vbox.add_child(menu_button)


## 显示暂停菜单
func show_pause_menu() -> void:
	visible = true
	get_tree().paused = true

	# 入场动画
	modulate = Color(1, 1, 1, 0)
	panel.scale = Vector2(0.8, 0.8)
	panel.pivot_offset = panel.size / 2.0

	var tween := create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.2)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)


## 隐藏暂停菜单
func hide_pause_menu() -> void:
	visible = false
	get_tree().paused = false


func _on_resume_pressed() -> void:
	hide_pause_menu()
	resume_requested.emit()


func _on_restart_pressed() -> void:
	hide_pause_menu()
	get_tree().reload_current_scene()
	restart_requested.emit()


func _on_menu_pressed() -> void:
	hide_pause_menu()
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
	main_menu_requested.emit()
