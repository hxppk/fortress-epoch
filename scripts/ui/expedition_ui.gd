extends Control
## ExpeditionUI -- 出征 UI
## 显示副本选择、三段式阶段进度、远程支援类型选择（轰炸/治疗/增益）、结算结果。

# ============================================================
# 信号
# ============================================================

signal expedition_selected(expedition_id: String)
signal support_requested(support_type: String)

# ============================================================
# 节点引用
# ============================================================

@onready var selection_panel: VBoxContainer = $SelectionPanel
@onready var progress_panel: VBoxContainer = $ProgressPanel
@onready var title_label: Label = $ProgressPanel/TitleLabel
@onready var progress_bar: ProgressBar = $ProgressPanel/ProgressBar
@onready var narration_label: Label = $ProgressPanel/NarrationLabel
@onready var support_button: Button = $ProgressPanel/SupportButton
@onready var result_label: Label = $ProgressPanel/ResultLabel

## 动态创建的支援按钮容器
var _support_container: HBoxContainer = null

## 阶段指示标签
var _phase_indicator: Label = null

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	# 隐藏旧的单一支援按钮（用新的多类型按钮替代）
	if support_button:
		support_button.visible = false
	visible = false

# ============================================================
# 公开方法
# ============================================================

## 显示副本选择界面（传入可用副本列表）
func show_selection(expeditions: Array) -> void:
	# 清空旧的动态按钮
	for child in selection_panel.get_children():
		if child is Button:
			child.queue_free()

	# 为每个副本创建选择按钮
	for exp_data: Dictionary in expeditions:
		var btn := Button.new()
		var name_str: String = exp_data.get("name", "未知")
		var diff: String = exp_data.get("difficulty", "?")
		var phases: Array = exp_data.get("phases", [])
		btn.text = "%s [%s] (%d阶段)" % [name_str, diff, phases.size()]
		btn.pressed.connect(func(): expedition_selected.emit(exp_data.get("id", "")))
		selection_panel.add_child(btn)

	# 添加"跳过出征"按钮
	var skip_btn := Button.new()
	skip_btn.text = "跳过出征"
	skip_btn.pressed.connect(func(): expedition_selected.emit(""))
	selection_panel.add_child(skip_btn)

	selection_panel.visible = true
	progress_panel.visible = false
	visible = true


## 显示出征进度界面（三段式）
func show_progress(expedition_name: String) -> void:
	selection_panel.visible = false
	progress_panel.visible = true
	title_label.text = expedition_name
	progress_bar.value = 0.0
	narration_label.text = "准备战斗..."
	result_label.text = ""
	result_label.visible = false

	# 隐藏旧支援按钮
	if support_button:
		support_button.visible = false

	# 创建阶段指示器
	_create_phase_indicator()

	visible = true


## 更新阶段显示
func update_phase(phase_index: int, phase_name: String, description: String) -> void:
	if _phase_indicator:
		_phase_indicator.text = "阶段 %d/3: %s" % [phase_index + 1, phase_name]
	narration_label.text = description
	# 更新进度条
	progress_bar.value = float(phase_index) / 3.0 * 100.0


## 更新进度（兼容旧接口）
func update_progress(message: String, progress: float) -> void:
	progress_bar.value = progress * 100.0
	if message != "":
		narration_label.text = message


## 显示远程支援按钮（3种类型）
func show_support_buttons(available_types: Array, remaining: int, support_types_config: Dictionary) -> void:
	# 移除旧的支援容器
	_remove_support_container()

	if remaining <= 0:
		return

	_support_container = HBoxContainer.new()
	_support_container.alignment = BoxContainer.ALIGNMENT_CENTER

	for support_type: String in available_types:
		var type_config: Dictionary = support_types_config.get(support_type, {})
		var type_name: String = type_config.get("name", support_type)
		var btn := Button.new()
		btn.text = type_name
		btn.tooltip_text = type_config.get("description", "")
		btn.custom_minimum_size = Vector2(80, 30)
		btn.pressed.connect(func(): support_requested.emit(support_type))
		_support_container.add_child(btn)

	# 添加剩余次数标签
	var count_label := Label.new()
	count_label.text = " (剩余%d次)" % remaining
	count_label.add_theme_font_size_override("font_size", 14)
	_support_container.add_child(count_label)

	progress_panel.add_child(_support_container)


## 更新远程支援按钮状态
func update_support_buttons(remaining: int) -> void:
	if remaining <= 0 and _support_container:
		# 禁用所有支援按钮
		for child in _support_container.get_children():
			if child is Button:
				child.disabled = true
		# 更新计数标签
		for child in _support_container.get_children():
			if child is Label:
				child.text = " (已用尽)"

	# 兼容旧接口
	if support_button:
		if remaining <= 0:
			support_button.disabled = true
			support_button.text = "支援已用尽"
		else:
			support_button.text = "远程支援 (%d)" % remaining


## 更新远程支援按钮（兼容旧接口）
func update_support_button(remaining: int) -> void:
	update_support_buttons(remaining)


## 显示结算结果
func show_result(success: bool, rewards: Dictionary) -> void:
	# 隐藏支援按钮
	_remove_support_container()
	if support_button:
		support_button.visible = false

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
	result_label.visible = true

	# 更新进度条
	progress_bar.value = 100.0 if success else progress_bar.value


## 隐藏出征面板
func hide_panel() -> void:
	_remove_support_container()
	_remove_phase_indicator()
	visible = false

# ============================================================
# 内部方法
# ============================================================

## 创建阶段指示标签
func _create_phase_indicator() -> void:
	_remove_phase_indicator()
	_phase_indicator = Label.new()
	_phase_indicator.text = "阶段 1/3"
	_phase_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_indicator.add_theme_font_size_override("font_size", 16)
	_phase_indicator.add_theme_color_override("font_color", Color(0.9, 0.9, 0.5))
	# 插入到 TitleLabel 之后
	var title_idx: int = title_label.get_index()
	progress_panel.add_child(_phase_indicator)
	progress_panel.move_child(_phase_indicator, title_idx + 1)


## 移除阶段指示标签
func _remove_phase_indicator() -> void:
	if _phase_indicator != null and is_instance_valid(_phase_indicator):
		_phase_indicator.queue_free()
		_phase_indicator = null


## 移除支援按钮容器
func _remove_support_container() -> void:
	if _support_container != null and is_instance_valid(_support_container):
		_support_container.queue_free()
		_support_container = null
