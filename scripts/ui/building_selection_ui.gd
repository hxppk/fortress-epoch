class_name BuildingSelectionUI
extends Control
## 引导阶段三选一建筑选择 UI
## 显示三张建筑卡牌供玩家选择，选择后发出信号并隐藏面板

signal building_selected(building_id: String)

## 当前可选的建筑 ID 列表
var building_options: Array = []
## 3 张卡牌节点的引用
var card_nodes: Array = []
## 面板是否处于激活状态
var is_active: bool = false
## 从 buildings.json 加载的建筑数据（key = building_id）
var buildings_data: Dictionary = {}

## 类别对应的颜色标识
const CATEGORY_COLORS: Dictionary = {
	"safety": Color(0.8, 0.2, 0.2),
	"economy": Color(0.9, 0.7, 0.2),
	"military": Color(0.2, 0.4, 0.8),
}

@onready var dim_overlay: ColorRect = $DimOverlay
@onready var title_label: Label = $VBoxContainer/Title
@onready var cards_container: HBoxContainer = $VBoxContainer/CardsContainer

## 每张卡牌的原始缩放，用于悬停动画还原
var _card_base_scales: Dictionary = {}


func _ready() -> void:
	_load_buildings_data()
	# 收集 3 张卡牌引用
	card_nodes = [
		$VBoxContainer/CardsContainer/Card1,
		$VBoxContainer/CardsContainer/Card2,
		$VBoxContainer/CardsContainer/Card3,
	]
	# 记录初始缩放 & 连接悬停/按钮信号
	for card in card_nodes:
		_card_base_scales[card] = card.scale
		card.mouse_entered.connect(_on_card_mouse_entered.bind(card))
		card.mouse_exited.connect(_on_card_mouse_exited.bind(card))
	hide_selection()


func _load_buildings_data() -> void:
	var file := FileAccess.open("res://data/buildings.json", FileAccess.READ)
	if file == null:
		push_error("BuildingSelectionUI: 无法打开 buildings.json")
		return
	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("BuildingSelectionUI: JSON 解析失败 — %s" % json.get_error_message())
		return

	var data: Dictionary = json.data
	if not data.has("buildings"):
		push_error("BuildingSelectionUI: JSON 缺少 buildings 字段")
		return

	for entry in data["buildings"]:
		buildings_data[entry["id"]] = entry


## 显示三选一界面
## options: 建筑 ID 数组，如 ["arrow_tower", "gold_mine", "barracks"]
func show_selection(options: Array) -> void:
	if options.size() < 3:
		push_error("BuildingSelectionUI: 需要至少 3 个建筑选项，当前: %d" % options.size())
		return

	building_options = options.slice(0, 3)
	is_active = true

	# 填充卡牌
	for i in range(3):
		_populate_card(card_nodes[i], building_options[i])
		card_nodes[i].visible = true
		card_nodes[i].scale = _card_base_scales[card_nodes[i]]

	visible = true
	# 暂停游戏（本节点 process_mode = ALWAYS，不受暂停影响）
	get_tree().paused = true


## 填充一张卡牌的显示数据
func _populate_card(card: Control, building_id: String) -> void:
	if not buildings_data.has(building_id):
		push_error("BuildingSelectionUI: 未知建筑 ID '%s'" % building_id)
		return

	var info: Dictionary = buildings_data[building_id]
	var vbox: VBoxContainer = card.get_node("VBoxContainer")

	# 颜色横幅
	var color_banner: ColorRect = vbox.get_node("ColorBanner")
	var category: String = info.get("category", "")
	color_banner.color = CATEGORY_COLORS.get(category, Color(0.5, 0.5, 0.5))

	# 名称
	var name_label: Label = vbox.get_node("NameLabel")
	name_label.text = info.get("name", building_id)

	# 描述
	var desc_label: Label = vbox.get_node("DescLabel")
	desc_label.text = info.get("description", "")

	# 关键数值（取等级 1 数据）
	var stats_label: Label = vbox.get_node("StatsLabel")
	stats_label.text = _format_stats(info)

	# 选择按钮 — 先断开所有旧连接再绑定新的
	var btn: Button = vbox.get_node("SelectButton")
	for conn: Dictionary in btn.pressed.get_connections():
		btn.pressed.disconnect(conn["callable"])
	btn.pressed.connect(_on_card_selected.bind(building_id))
	btn.text = "选择"


## 格式化等级 1 的关键数值为可读文本
func _format_stats(info: Dictionary) -> String:
	var levels: Array = info.get("levels", [])
	if levels.is_empty():
		return ""

	var lv1: Dictionary = levels[0]
	var lines: PackedStringArray = []
	var category: String = info.get("category", "")

	match category:
		"safety":
			if lv1.has("damage"):
				lines.append("伤害: %s" % str(lv1["damage"]))
			if lv1.has("range"):
				lines.append("射程: %s" % str(lv1["range"]))
			if lv1.has("attack_speed"):
				lines.append("攻速: %ss" % str(lv1["attack_speed"]))
		"economy":
			if lv1.has("production"):
				lines.append("产出: %s 金/次" % str(lv1["production"]))
			if lv1.has("production_interval"):
				lines.append("间隔: %ss" % str(lv1["production_interval"]))
			if lv1.has("kill_gold_bonus"):
				lines.append("击杀加成: +%d%%" % int(lv1["kill_gold_bonus"] * 100))
		"military":
			if lv1.has("phys_attack_bonus"):
				lines.append("物攻: +%s" % str(lv1["phys_attack_bonus"]))
			if lv1.has("magic_attack_bonus"):
				lines.append("法攻: +%s" % str(lv1["magic_attack_bonus"]))
			if lv1.has("hp_bonus"):
				lines.append("生命: +%s" % str(lv1["hp_bonus"]))

	return "\n".join(lines)


## 卡牌被选中
func _on_card_selected(building_id: String) -> void:
	if not is_active:
		return
	hide_selection()
	building_selected.emit(building_id)


## 隐藏选择界面并恢复游戏
func hide_selection() -> void:
	is_active = false
	visible = false
	get_tree().paused = false


## 鼠标悬停卡牌 — 缩放至 1.05
func _on_card_mouse_entered(card: Control) -> void:
	if not is_active:
		return
	var base_scale: Vector2 = _card_base_scales.get(card, Vector2.ONE)
	var tween := create_tween()
	tween.tween_property(card, "scale", base_scale * 1.05, 0.1).set_ease(Tween.EASE_OUT)


## 鼠标离开卡牌 — 恢复原始缩放
func _on_card_mouse_exited(card: Control) -> void:
	if not is_active:
		return
	var base_scale: Vector2 = _card_base_scales.get(card, Vector2.ONE)
	var tween := create_tween()
	tween.tween_property(card, "scale", base_scale, 0.1).set_ease(Tween.EASE_OUT)
