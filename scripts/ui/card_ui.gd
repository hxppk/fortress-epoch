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
## 效果预览面板
var _preview_panel: PanelContainer = null
## 悬停计时器（延迟显示预览）
var _hover_timer: float = 0.0
var _is_hovering: bool = false
const PREVIEW_HOVER_DELAY: float = 0.5  # 悬停 0.5 秒后显示预览

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

	# 装备卡额外标识：在稀有度文字后追加槽位标签
	var card_category: String = data.get("category", "")
	if card_category == "equipment":
		var slot: String = data.get("slot", "")
		var slot_label: String = _get_slot_label(slot)
		if slot_label != "":
			rarity_label.text = rarity_label.text + " · " + slot_label

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
		"green":
			return Color(0.18, 0.75, 0.35)
		_:
			return Color(0.7, 0.7, 0.7)


## 装备槽位中文标签
func _get_slot_label(slot: String) -> String:
	match slot:
		"weapon":
			return "武器"
		"armor":
			return "护甲"
		"accessory":
			return "饰品"
		_:
			return ""


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


## 悬停：缩放 1.05 + 开始预览计时
func _on_mouse_entered() -> void:
	if is_selected:
		return
	_is_hovering = true
	_hover_timer = 0.0
	pivot_offset = size / 2.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "scale", base_scale * 1.05, 0.15)


## 离开：恢复原始缩放 + 隐藏预览
func _on_mouse_exited() -> void:
	_is_hovering = false
	_hover_timer = 0.0
	_hide_preview()
	if is_selected:
		return
	pivot_offset = size / 2.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "scale", base_scale, 0.15)


## 选择按钮点击
func _on_select_button_pressed() -> void:
	_hide_preview()
	card_clicked.emit(card_data)


func _process(delta: float) -> void:
	# 悬停延迟显示效果预览
	if _is_hovering and _preview_panel == null and not is_selected:
		_hover_timer += delta
		if _hover_timer >= PREVIEW_HOVER_DELAY:
			_show_preview()


## 显示效果预览面板
func _show_preview() -> void:
	if _preview_panel != null:
		return

	var effects: Array = card_data.get("effects", [])
	if effects.is_empty():
		return

	_preview_panel = PanelContainer.new()
	_preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 暗色半透明背景
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.92)
	panel_style.border_color = Color(0.4, 0.6, 0.9, 0.8)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(8.0)
	_preview_panel.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 标题
	var title := Label.new()
	title.text = "选择后效果:"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	# 每个效果
	for effect: Dictionary in effects:
		var effect_label := Label.new()
		effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		effect_label.add_theme_font_size_override("font_size", 13)

		var effect_type: String = effect.get("type", "")
		var stat: String = effect.get("stat", "")
		var value = effect.get("value", 0)
		var text: String = ""
		var text_color: Color = Color(0.5, 1.0, 0.5)  # 绿色=增益

		match effect_type:
			"stat_boost":
				if value is float and value < 1.0 and value > 0.0:
					text = "%s: +%d%%" % [_translate_stat(stat), int(value * 100)]
				else:
					text = "%s: +%s" % [_translate_stat(stat), str(value)]
			"resource":
				text = "%s: +%s" % [_translate_stat(stat), str(value)]
				text_color = Color(1.0, 0.9, 0.3)  # 金色=资源
			"equip":
				var slot: String = effect.get("slot", "")
				text = "装备 [%s]: %s +%s" % [_translate_slot(slot), _translate_stat(stat), str(value)]
			_:
				text = "%s: %s" % [effect_type, str(value)]

		effect_label.text = text
		effect_label.add_theme_color_override("font_color", text_color)
		vbox.add_child(effect_label)

	_preview_panel.add_child(vbox)

	# 在卡牌右侧显示
	_preview_panel.position = Vector2(size.x + 8.0, 0.0)
	add_child(_preview_panel)

	# 淡入动画
	_preview_panel.modulate = Color(1, 1, 1, 0)
	var tween := _preview_panel.create_tween()
	tween.tween_property(_preview_panel, "modulate:a", 1.0, 0.15)


## 隐藏效果预览面板
func _hide_preview() -> void:
	if _preview_panel != null and is_instance_valid(_preview_panel):
		_preview_panel.queue_free()
		_preview_panel = null


## 属性名翻译
func _translate_stat(stat: String) -> String:
	match stat:
		"attack": return "攻击力"
		"defense": return "防御力"
		"hp": return "生命值"
		"max_hp": return "最大生命"
		"speed": return "移动速度"
		"attack_speed": return "攻击速度"
		"crit_rate": return "暴击率"
		"spell_power": return "法术强度"
		"gold": return "金币"
		"crystal": return "水晶"
		"attack_range": return "攻击范围"
		_: return stat


## 装备槽位翻译
func _translate_slot(slot: String) -> String:
	match slot:
		"weapon": return "武器"
		"armor": return "护甲"
		"accessory": return "饰品"
		_: return slot
