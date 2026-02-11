extends Control
## ExpeditionUI — 出征小窗 UI
## 显示副本选择、出征进度、文字播报、远程支援按钮、结算结果。

# ============================================================
# 信号
# ============================================================

signal expedition_selected(expedition_id: String)
signal support_requested()

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

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	if support_button:
		support_button.pressed.connect(func(): support_requested.emit())
	visible = false

# ============================================================
# 公开方法
# ============================================================

## 显示副本选择界面（传入可用副本列表）
func show_selection(expeditions: Array) -> void:
	# 清空旧的动态按钮（跳过静态场景节点如 SelectTitle）
	for child in selection_panel.get_children():
		if child is Button:
			child.queue_free()

	# 为每个副本创建选择按钮
	for exp_data: Dictionary in expeditions:
		var btn := Button.new()
		var name_str: String = exp_data.get("name", "未知")
		var diff: String = exp_data.get("difficulty", "?")
		btn.text = "%s [%s]" % [name_str, diff]
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


## 显示出征进度界面
func show_progress(expedition_name: String) -> void:
	selection_panel.visible = false
	progress_panel.visible = true
	title_label.text = expedition_name
	progress_bar.value = 0.0
	narration_label.text = ""
	result_label.text = ""
	result_label.visible = false
	support_button.visible = true
	visible = true


## 更新进度
func update_progress(message: String, progress: float) -> void:
	progress_bar.value = progress * 100.0
	if message != "":
		narration_label.text = message


## 更新远程支援按钮
func update_support_button(remaining: int) -> void:
	if remaining <= 0:
		support_button.disabled = true
		support_button.text = "支援已用尽"
	else:
		support_button.text = "远程支援 (%d)" % remaining


## 显示结算结果
func show_result(success: bool, rewards: Dictionary) -> void:
	support_button.visible = false
	var text: String = "出征%s！\n" % ("胜利" if success else "失败")
	for key: String in rewards:
		if key == "bonus_card":
			if rewards[key]:
				text += "获得额外卡牌！\n"
		else:
			text += "%s: +%d\n" % [key, int(rewards[key])]
	result_label.text = text
	result_label.visible = true


## 隐藏出征面板
func hide_panel() -> void:
	visible = false
