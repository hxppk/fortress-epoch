class_name BuildingUpgradeUI
extends Control
## BuildingUpgradeUI — 建筑升级交互面板
## 点击已放置的建筑时弹出，显示当前属性 vs 下一级属性，可执行升级。

# ============================================================
# 信号
# ============================================================

signal upgrade_performed(building: Node, new_level: int)
signal panel_closed()

# ============================================================
# 常量
# ============================================================

const BUILDINGS_JSON_PATH: String = "res://data/buildings.json"

## 属性显示名称映射（按建筑类型）
const STAT_LABELS: Dictionary = {
	"arrow_tower": {
		"damage": "伤害",
		"range": "射程",
		"attack_speed": "攻速",
	},
	"gold_mine": {
		"production": "产出",
		"production_interval": "间隔",
		"kill_gold_bonus": "击杀加成",
	},
	"barracks": {
		"phys_attack_bonus": "攻击加成",
		"hp_bonus": "生命加成",
		"armor_bonus": "护甲加成",
	},
}

## 资源类型中文名
const RESOURCE_NAMES: Dictionary = {
	"gold": "金币",
	"crystal": "水晶",
	"badge": "徽章",
	"exp": "经验",
}

## 数值越低越好的属性（如攻速间隔越短越好）
const LOWER_IS_BETTER: Array = ["attack_speed", "production_interval"]

# ============================================================
# 属性
# ============================================================

## 当前选中的建筑
var current_building: Node = null

## 面板是否可见
var is_visible_panel: bool = false

## 从 buildings.json 缓存的数据 { "building_id": { ... } }
var buildings_data: Dictionary = {}

# ============================================================
# 子节点引用
# ============================================================

@onready var panel_container: PanelContainer = $PanelContainer
@onready var title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var current_values: Label = $PanelContainer/MarginContainer/VBoxContainer/StatsContainer/CurrentStats/CurrentValues
@onready var next_values: Label = $PanelContainer/MarginContainer/VBoxContainer/StatsContainer/NextStats/NextValues
@onready var cost_label: Label = $PanelContainer/MarginContainer/VBoxContainer/CostLabel
@onready var upgrade_button: Button = $PanelContainer/MarginContainer/VBoxContainer/ButtonsContainer/UpgradeButton
@onready var close_button: Button = $PanelContainer/MarginContainer/VBoxContainer/ButtonsContainer/CloseButton

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	_load_buildings_data()

	# 连接按钮信号
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	close_button.pressed.connect(_on_close_pressed)

	# 隐藏面板
	hide_panel()


func _input(event: InputEvent) -> void:
	if not is_visible_panel:
		return

	# 点击面板外区域自动关闭
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			# 检查鼠标是否在面板区域内
			var panel_rect: Rect2 = panel_container.get_global_rect()
			if not panel_rect.has_point(mouse_event.global_position):
				hide_panel()
				get_viewport().set_input_as_handled()

# ============================================================
# 公有方法
# ============================================================

## 显示升级面板，传入建筑引用
func show_panel(building: Node) -> void:
	if building == null:
		return

	current_building = building
	is_visible_panel = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	_populate_panel()


## 隐藏面板
func hide_panel() -> void:
	current_building = null
	is_visible_panel = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# ============================================================
# 私有方法 — 面板数据
# ============================================================

## 填充面板数据（名称、当前等级、当前/下一级属性、费用）
func _populate_panel() -> void:
	if current_building == null:
		return

	var building_id: String = current_building.building_id
	var level: int = current_building.current_level

	# 获取建筑数据
	var bdata: Dictionary = buildings_data.get(building_id, {})
	if bdata.is_empty():
		push_warning("BuildingUpgradeUI: 未找到建筑数据 id=%s" % building_id)
		return

	var building_name: String = bdata.get("name", building_id)

	# 标题
	title_label.text = "%s Lv%d" % [building_name, level]

	# 更新属性对比显示
	_update_stats_display()

	# 费用与按钮状态
	var is_max_level: bool = level >= 3
	if is_max_level:
		cost_label.text = "已达最高等级"
		upgrade_button.text = "MAX"
		upgrade_button.disabled = true
	else:
		# 获取升级费用
		var cost: Dictionary = current_building.get_upgrade_cost()
		cost_label.text = "费用: %s" % _format_cost(cost)

		# 检查资源是否够
		var can_afford: bool = current_building.can_upgrade()
		upgrade_button.text = "升级"
		upgrade_button.disabled = not can_afford


## 更新属性对比显示
func _update_stats_display() -> void:
	if current_building == null:
		return

	var building_id: String = current_building.building_id
	var level: int = current_building.current_level

	var bdata: Dictionary = buildings_data.get(building_id, {})
	if bdata.is_empty():
		return

	var levels: Array = bdata.get("levels", [])
	var level_index: int = level - 1

	# 当前等级数据
	var cur_level_data: Dictionary = {}
	if level_index >= 0 and level_index < levels.size():
		cur_level_data = levels[level_index]

	# 下一级数据
	var next_level_data: Dictionary = {}
	var next_index: int = level_index + 1
	if next_index >= 0 and next_index < levels.size():
		next_level_data = levels[next_index]

	# 填充当前属性
	current_values.text = _format_building_stats(building_id, cur_level_data)

	# 填充下一级属性（带绿色高亮）
	if next_level_data.is_empty():
		next_values.text = "---"
	else:
		next_values.text = _format_building_stats_with_highlight(building_id, cur_level_data, next_level_data)


## 格式化属性文本
func _format_building_stats(building_id: String, level_data: Dictionary) -> String:
	if level_data.is_empty():
		return "---"

	var stat_keys: Dictionary = STAT_LABELS.get(building_id, {})
	if stat_keys.is_empty():
		return "---"

	var lines: PackedStringArray = PackedStringArray()
	for key: String in stat_keys:
		var label_name: String = stat_keys[key]
		var value: Variant = level_data.get(key, "--")
		lines.append("%s: %s" % [label_name, str(value)])

	return "\n".join(lines)


## 格式化下一级属性文本（变化值用 BBCode 绿色标记，实际用纯文本 + 箭头表示变化）
func _format_building_stats_with_highlight(building_id: String, cur_data: Dictionary, next_data: Dictionary) -> String:
	if next_data.is_empty():
		return "---"

	var stat_keys: Dictionary = STAT_LABELS.get(building_id, {})
	if stat_keys.is_empty():
		return "---"

	var lines: PackedStringArray = PackedStringArray()
	for key: String in stat_keys:
		var label_name: String = stat_keys[key]
		var cur_val: Variant = cur_data.get(key, 0)
		var next_val: Variant = next_data.get(key, 0)
		var cur_f: float = float(cur_val)
		var next_f: float = float(next_val)

		var value_str: String = str(next_val)

		# 判断是否有变化
		var is_improved: bool = false
		if LOWER_IS_BETTER.has(key):
			is_improved = next_f < cur_f
		else:
			is_improved = next_f > cur_f

		if is_improved:
			# 用色彩标识符来提示变化（Label 不支持 BBCode，用符号标记）
			value_str = "%s ^" % str(next_val)

		lines.append("%s: %s" % [label_name, value_str])

	return "\n".join(lines)


## 格式化费用文本
func _format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "免费"

	var parts: PackedStringArray = PackedStringArray()
	for resource_type: String in cost:
		var amount: int = int(cost[resource_type])
		var res_name: String = RESOURCE_NAMES.get(resource_type, resource_type)
		parts.append("%d %s" % [amount, res_name])

	return ", ".join(parts)

# ============================================================
# 信号回调
# ============================================================

## 执行升级
func _on_upgrade_pressed() -> void:
	if current_building == null:
		return

	if not current_building.can_upgrade():
		return

	var success: bool = current_building.upgrade()
	if success:
		var new_level: int = current_building.current_level
		upgrade_performed.emit(current_building, new_level)

		# 刷新面板显示
		_populate_panel()


## 关闭面板
func _on_close_pressed() -> void:
	hide_panel()
	panel_closed.emit()

# ============================================================
# 私有方法 — 数据加载
# ============================================================

## 加载 buildings.json 并按 id 索引缓存
func _load_buildings_data() -> void:
	if not FileAccess.file_exists(BUILDINGS_JSON_PATH):
		push_error("BuildingUpgradeUI: buildings.json 不存在: %s" % BUILDINGS_JSON_PATH)
		return

	var file: FileAccess = FileAccess.open(BUILDINGS_JSON_PATH, FileAccess.READ)
	var json_text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_text)
	if parse_result != OK:
		push_error("BuildingUpgradeUI: buildings.json 解析失败: %s" % json.get_error_message())
		return

	var data: Dictionary = json.data
	var buildings_array: Array = data.get("buildings", [])

	for building: Dictionary in buildings_array:
		var bid: String = building.get("id", "")
		if bid != "":
			buildings_data[bid] = building
