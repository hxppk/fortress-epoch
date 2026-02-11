class_name CardUI
extends PanelContainer
## 单张卡牌的 UI 渲染组件 — 边框色、名称、效果文字、悬停动画

signal card_clicked(card_data: Dictionary)

## 卡牌数据（从 CardData 或直接从 JSON dict）
var card_data: Dictionary = {}
## 是否已被选中
var is_selected: bool = false
## 基础缩放
var base_scale: Vector2 = Vector2.ONE

@onready var rarity_banner: ColorRect = $VBoxContainer/RarityBanner
@onready var category_icon: ColorRect = $VBoxContainer/CategoryIcon
@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var desc_label: Label = $VBoxContainer/DescLabel
@onready var rarity_label: Label = $VBoxContainer/RarityLabel
@onready var select_button: Button = $VBoxContainer/SelectButton


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	select_button.pressed.connect(_on_select_button_pressed)
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = size / 2.0


## 用卡牌数据填充 UI
func setup(data: Dictionary) -> void:
	card_data = data

	# 确保节点就绪
	if not is_node_ready():
		await ready

	# 名称
	name_label.text = data.get("name", "未知卡牌")

	# 描述
	desc_label.text = data.get("description", "")

	# 稀有度
	var rarity: String = data.get("rarity", "common")
	var rarity_color := _get_rarity_color(rarity)

	# 稀有度横幅颜色
	rarity_banner.color = rarity_color

	# 稀有度文字
	rarity_label.text = _get_rarity_text(rarity)
	rarity_label.add_theme_color_override("font_color", rarity_color)

	# 边框颜色（通过 StyleBoxFlat）
	var style := get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		var new_style := style.duplicate() as StyleBoxFlat
		new_style.border_color = rarity_color
		add_theme_stylebox_override("panel", new_style)

	# 类型图标颜色
	var icon_color_key: String = data.get("icon_color", "blue")
	category_icon.color = _get_category_color(icon_color_key)

	# 重置状态
	is_selected = false
	modulate = Color.WHITE
	scale = base_scale
	pivot_offset = size / 2.0


## 稀有度对应颜色
func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common":
			return Color(0.8, 0.8, 0.8)
		"uncommon":
			return Color(0.29, 0.56, 0.85)
		"epic":
			return Color(0.61, 0.35, 0.71)
		"legendary":
			return Color(0.95, 0.77, 0.06)
		_:
			return Color(0.8, 0.8, 0.8)


## 稀有度中文文字
func _get_rarity_text(rarity: String) -> String:
	match rarity:
		"common":
			return "普通"
		"uncommon":
			return "精良"
		"epic":
			return "史诗"
		"legendary":
			return "传说"
		_:
			return "普通"


## 类型图标颜色映射
func _get_category_color(icon_color: String) -> Color:
	match icon_color:
		"red":
			return Color(0.9, 0.25, 0.2)
		"blue":
			return Color(0.29, 0.56, 0.85)
		"gold":
			return Color(0.95, 0.77, 0.06)
		_:
			return Color(0.7, 0.7, 0.7)


## 选中动画：缩放到 1.1 + 边框发光
func play_select_animation() -> void:
	is_selected = true
	pivot_offset = size / 2.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.3)

	# 边框发光效果 — 增亮边框
	var style := get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		var glow_style := style.duplicate() as StyleBoxFlat
		glow_style.border_width_left = 3
		glow_style.border_width_top = 3
		glow_style.border_width_right = 3
		glow_style.border_width_bottom = 3
		glow_style.border_color = glow_style.border_color.lightened(0.3)
		add_theme_stylebox_override("panel", glow_style)


## 未选中淡出：alpha -> 0，缩放 -> 0.8
func play_dismiss_animation() -> void:
	pivot_offset = size / 2.0
	var tween := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), 0.35)


## 悬停：缩放 1.05
func _on_mouse_entered() -> void:
	if is_selected:
		return
	pivot_offset = size / 2.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "scale", base_scale * 1.05, 0.15)


## 离开：恢复原始缩放
func _on_mouse_exited() -> void:
	if is_selected:
		return
	pivot_offset = size / 2.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "scale", base_scale, 0.15)


## 选择按钮点击
func _on_select_button_pressed() -> void:
	card_clicked.emit(card_data)
