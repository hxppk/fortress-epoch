extends Control
## ExpeditionUI -- 出征 UI（底部条布局）
## 选择阶段用居中弹窗，进度/支援阶段用底部条，结算用居中弹窗。

# ============================================================
# 信号
# ============================================================

signal expedition_selected(expedition_id: String)
signal support_requested(support_type: String)

# ============================================================
# 节点引用
# ============================================================

@onready var selection_overlay: PanelContainer = $SelectionOverlay
@onready var select_content: VBoxContainer = $SelectionOverlay/SelectContent
@onready var bottom_bar: PanelContainer = $BottomBar
@onready var bar_content: HBoxContainer = $BottomBar/BarContent
@onready var info_label: Label = $BottomBar/BarContent/InfoLabel
@onready var progress_bar: ProgressBar = $BottomBar/BarContent/ProgressBar
@onready var timer_label: Label = $BottomBar/BarContent/TimerLabel
@onready var result_overlay: PanelContainer = $ResultOverlay
@onready var result_label: Label = $ResultOverlay/ResultLabel

## 动态创建的支援按钮容器
var _support_container: HBoxContainer = null

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	visible = false

# ============================================================
# 公开方法
# ============================================================

## 显示副本选择界面（居中弹窗）
func show_selection(expeditions: Array) -> void:
	# 清空旧的动态按钮（保留 SelectTitle）
	for child in select_content.get_children():
		if child is Button:
			child.queue_free()

	for exp_data: Dictionary in expeditions:
		var btn := Button.new()
		var name_str: String = exp_data.get("name", "未知")
		var diff: String = exp_data.get("difficulty", "?")
		var phases: Array = exp_data.get("phases", [])
		btn.text = "%s [%s] (%d阶段)" % [name_str, diff, phases.size()]
		btn.pressed.connect(func(): expedition_selected.emit(exp_data.get("id", "")))
		select_content.add_child(btn)

	var skip_btn := Button.new()
	skip_btn.text = "跳过出征"
	skip_btn.pressed.connect(func(): expedition_selected.emit(""))
	select_content.add_child(skip_btn)

	selection_overlay.visible = true
	bottom_bar.visible = false
	result_overlay.visible = false
	visible = true


## 显示出征进度（底部条）
func show_progress(expedition_name: String) -> void:
	selection_overlay.visible = false
	result_overlay.visible = false
	bottom_bar.visible = true

	info_label.text = expedition_name
	progress_bar.value = 0.0
	timer_label.text = "--s"

	visible = true


## 更新阶段显示
func update_phase(phase_index: int, phase_name: String, description: String) -> void:
	var title_base: String = info_label.text.split(" | ")[0] if " | " in info_label.text else info_label.text
	info_label.text = "%s | %d/3: %s" % [title_base, phase_index + 1, phase_name]
	progress_bar.value = float(phase_index) / 3.0 * 100.0
	# 用 tooltip 保留详细描述
	info_label.tooltip_text = description


## 更新倒计时显示
func update_timer(remaining: float) -> void:
	if timer_label:
		timer_label.text = "%ds" % ceili(maxf(remaining, 0.0))


## 更新进度（兼容旧接口）
func update_progress(message: String, progress: float) -> void:
	progress_bar.value = progress * 100.0
	if message != "":
		info_label.tooltip_text = message


## 显示远程支援按钮（追加到底部条右侧）
func show_support_buttons(available_types: Array, remaining: int, support_types_config: Dictionary) -> void:
	_remove_support_container()

	if remaining <= 0:
		return

	_support_container = HBoxContainer.new()
	_support_container.add_theme_constant_override("separation", 4)

	for support_type: String in available_types:
		var type_config: Dictionary = support_types_config.get(support_type, {})
		var type_name: String = type_config.get("name", support_type)
		var btn := Button.new()
		btn.text = type_name
		btn.tooltip_text = type_config.get("description", "")
		btn.custom_minimum_size = Vector2(50, 0)
		btn.pressed.connect(func(): support_requested.emit(support_type))
		_support_container.add_child(btn)

	var count_label := Label.new()
	count_label.text = "(%d)" % remaining
	count_label.add_theme_font_size_override("font_size", 12)
	_support_container.add_child(count_label)

	bar_content.add_child(_support_container)


## 更新远程支援按钮状态
func update_support_buttons(remaining: int) -> void:
	if remaining <= 0 and _support_container:
		for child in _support_container.get_children():
			if child is Button:
				child.disabled = true
		for child in _support_container.get_children():
			if child is Label:
				child.text = "(0)"


## 兼容旧接口
func update_support_button(remaining: int) -> void:
	update_support_buttons(remaining)


## 显示结算结果（居中弹窗）
func show_result(success: bool, rewards: Dictionary) -> void:
	_remove_support_container()
	bottom_bar.visible = false

	var text: String = "出征%s!\n" % ("胜利" if success else "失败")
	for key: String in rewards:
		if key == "bonus_card":
			if rewards[key]:
				text += "获得额外卡牌!\n"
		elif key.ends_with("_chance"):
			continue
		else:
			text += "%s: +%d\n" % [key, int(rewards[key])]

	result_label.text = text
	result_overlay.visible = true
	visible = true


## 隐藏出征面板
func hide_panel() -> void:
	_remove_support_container()
	selection_overlay.visible = false
	bottom_bar.visible = false
	result_overlay.visible = false
	visible = false

# ============================================================
# 内部方法
# ============================================================

func _remove_support_container() -> void:
	if _support_container != null and is_instance_valid(_support_container):
		_support_container.queue_free()
		_support_container = null
