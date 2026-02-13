extends Control
## 主菜单 — 含局外成长展示（英雄信息 / 货币 / 研究面板）

@onready var start_button: Button = $VBoxContainer/StartButton
@onready var quit_button: Button = $VBoxContainer/QuitButton

# 动态创建的 UI 引用
var currency_label: Label = null
var hero_level_label: Label = null
var hero_exp_label: Label = null
var hero_bonus_label: Label = null
var research_labels: Dictionary = {}   # { "arrow_tower": Label, ... }
var research_buttons: Dictionary = {}  # { "arrow_tower": Button, ... }


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	start_button.grab_focus()

	# 扩大 VBox 容纳局外 UI
	var vbox: VBoxContainer = $VBoxContainer
	vbox.offset_top = -220.0
	vbox.offset_bottom = 220.0

	_build_meta_ui()
	_refresh_meta_display()


# ============================================================
# 构建局外 UI
# ============================================================

func _build_meta_ui() -> void:
	var vbox: VBoxContainer = $VBoxContainer

	# --- 货币栏（插入到 Subtitle 后面，StartButton 前面） ---
	currency_label = Label.new()
	currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	currency_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	vbox.add_child(currency_label)
	vbox.move_child(currency_label, 2)  # Title(0), Subtitle(1), currency(2)

	# --- 英雄信息面板 ---
	var hero_panel := VBoxContainer.new()
	hero_panel.name = "HeroPanel"
	hero_panel.add_theme_constant_override("separation", 2)

	hero_level_label = Label.new()
	hero_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_panel.add_child(hero_level_label)

	hero_exp_label = Label.new()
	hero_exp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_exp_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	hero_panel.add_child(hero_exp_label)

	hero_bonus_label = Label.new()
	hero_bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_bonus_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	hero_panel.add_child(hero_bonus_label)

	vbox.add_child(hero_panel)
	vbox.move_child(hero_panel, 3)  # 货币栏之后

	# --- 研究面板（QuitButton 之后） ---
	var sep := HSeparator.new()
	vbox.add_child(sep)

	var research_title := Label.new()
	research_title.text = "── 建筑研究 ──"
	research_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	research_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))
	vbox.add_child(research_title)

	var types: Array = ["arrow_tower", "gold_mine", "barracks"]
	var names: Dictionary = {"arrow_tower": "箭塔", "gold_mine": "金矿", "barracks": "兵营"}

	for type_id: String in types:
		var hbox := HBoxContainer.new()
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", 10)

		var info_label := Label.new()
		info_label.custom_minimum_size = Vector2(140, 0)
		hbox.add_child(info_label)
		research_labels[type_id] = info_label

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, 0)
		btn.pressed.connect(_on_research_upgrade.bind(type_id))
		hbox.add_child(btn)
		research_buttons[type_id] = btn

		vbox.add_child(hbox)


# ============================================================
# 刷新局外数据显示
# ============================================================

func _refresh_meta_display() -> void:
	if not is_instance_valid(SaveManager) or SaveManager.progression == null:
		return

	var prog: MetaProgression = SaveManager.progression

	# 货币
	var crystal: int = prog.get_currency("crystal")
	var badge: int = prog.get_currency("badge")
	currency_label.text = "水晶: %d    徽章: %d" % [crystal, badge]

	# 英雄信息
	var hero_id: String = "wolf_knight"
	var level: int = prog.get_hero_level(hero_id)
	var exp: int = prog.data["hero_progress"][hero_id].get("exp", 0)
	var next_threshold: int = 0
	if level < MetaProgression.HERO_EXP_THRESHOLDS.size():
		next_threshold = MetaProgression.HERO_EXP_THRESHOLDS[level]

	hero_level_label.text = "白狼骑士 Lv.%d" % level
	if next_threshold > 0:
		hero_exp_label.text = "EXP: %d / %d" % [exp, next_threshold]
	else:
		hero_exp_label.text = "EXP: %d (MAX)" % exp

	var bonus: Dictionary = prog.get_hero_stat_bonus(hero_id)
	var pct: float = bonus.get("attack_pct", 0.0)
	if pct > 0.0:
		hero_bonus_label.text = "全属性 +%.0f%%" % (pct * 100)
		hero_bonus_label.visible = true
	else:
		hero_bonus_label.visible = false

	# 研究面板
	var names: Dictionary = {"arrow_tower": "箭塔", "gold_mine": "金矿", "barracks": "兵营"}
	for type_id: String in research_labels:
		var lv: int = prog.get_research_level(type_id)
		var cost: int = prog.get_research_cost(type_id)
		var rlabel: Label = research_labels[type_id]
		var rbtn: Button = research_buttons[type_id]
		rlabel.text = "%s研究 Lv.%d/3" % [names[type_id], lv]
		if cost >= 0:
			rbtn.text = "升级 (%d水晶)" % cost
			rbtn.disabled = crystal < cost
		else:
			rbtn.text = "已满级"
			rbtn.disabled = true


# ============================================================
# 研究升级回调
# ============================================================

func _on_research_upgrade(type_id: String) -> void:
	if SaveManager.upgrade_research(type_id):
		_refresh_meta_display()


# ============================================================
# 导航
# ============================================================

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main/game_session.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
