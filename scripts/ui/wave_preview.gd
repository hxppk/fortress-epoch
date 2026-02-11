extends Control
## WavePreview — 波次预告面板
## 在新波开始前短暂显示即将出现的敌人信息（类型、数量、方向），
## 2.5 秒后自动淡出隐藏。

# ============================================================
# 信号
# ============================================================

## 预告面板关闭时发出
signal preview_dismissed()

# ============================================================
# 子节点引用
# ============================================================

@onready var _title_label: Label = $VBox/TitleLabel
@onready var _enemies_label: Label = $VBox/EnemiesLabel
@onready var _routes_label: Label = $VBox/RoutesLabel

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	visible = false

# ============================================================
# 公开方法
# ============================================================

## 显示波次预告
## wave_data: { "label": "热身", "enemies": [...], "spawn_routes": [...], "tension": int }
func show_preview(wave_data: Dictionary) -> void:
	# 构建预告内容
	var label_text: String = wave_data.get("label", "???")
	var tension: int = int(wave_data.get("tension", 1))

	# 标题
	_title_label.text = "第 %s 波" % label_text  # 实际整合时可传入波次编号

	# 敌人列表
	var enemies_config: Array = wave_data.get("enemies", [])
	var enemy_text: String = ""
	for entry: Dictionary in enemies_config:
		var etype: String = entry.get("type", "???")
		var count: int = int(entry.get("count", 0))
		var is_continuous: bool = entry.get("spawn_continuous", false)

		var type_name: String = _get_enemy_display_name(etype)
		if is_continuous:
			enemy_text += "· %s (持续出现)\n" % type_name
		elif count > 0:
			enemy_text += "· %s x%d\n" % [type_name, count]
	_enemies_label.text = enemy_text

	# 路线方向
	var routes: Array = wave_data.get("spawn_routes", [])
	var route_text: String = ""
	for route: String in routes:
		route_text += _get_route_arrow(route) + " "
	_routes_label.text = "进攻方向: %s" % route_text.strip_edges()

	# 紧张度指示（用颜色区分紧张程度）
	var tension_color: Color = _get_tension_color(tension)
	_title_label.add_theme_color_override("font_color", tension_color)

	# 显示并 2.5 秒后自动淡出隐藏
	visible = true
	modulate = Color.WHITE

	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		visible = false
		preview_dismissed.emit()
	)

# ============================================================
# 辅助方法
# ============================================================

## 敌人类型中文名映射
func _get_enemy_display_name(type: String) -> String:
	match type:
		"slime": return "史莱姆"
		"goblin": return "哥布林"
		"skeleton": return "骷髅兵"
		"ghost": return "幽灵"
		"zombie": return "僵尸"
		"orc_elite": return "兽人精英"
		"demon_boss": return "恶魔领主"
		_: return type


## 路线方向箭头
func _get_route_arrow(route: String) -> String:
	match route:
		"north": return "↑北"
		"east": return "→东"
		"south": return "↓南"
		"west": return "←西"
		_: return "?"


## 紧张度颜色
func _get_tension_color(tension: int) -> Color:
	match tension:
		1: return Color.WHITE
		2: return Color.YELLOW
		3: return Color.ORANGE
		4: return Color.ORANGE_RED
		5: return Color.RED
		_: return Color.WHITE
