class_name UIController
extends Node
## UIController -- UI 面板协调控制器
## 从 GameSession 抽取，管理所有 UI 面板的显示/隐藏和用户交互回调。

# ============================================================
# 信号（通知 GameSession 执行游戏逻辑）
# ============================================================

signal card_selection_done()
signal expedition_skipped()
signal expedition_selected(expedition_id: String)
signal building_selection_made(building_id: String)
signal restart_requested()
signal main_menu_requested()
signal pause_requested()
signal support_requested(support_type: String)

# ============================================================
# UI 节点引用
# ============================================================

var hud: Control = null
var building_selection: Control = null
var building_upgrade_panel: Control = null
var card_selection: Control = null
var wave_preview: Control = null
var boss_hp_bar: Control = null
var expedition_panel: Control = null
var result_screen: Control = null
var pause_menu: Control = null
var ui_layer: CanvasLayer = null

# ============================================================
# 游戏系统引用（只读查询）
# ============================================================

var card_pool: CardPool = null
var card_effects: CardEffects = null
var wave_spawner: WaveSpawner = null
var current_hero: HeroBase = null

# ============================================================
# 初始化
# ============================================================

func initialize(config: Dictionary) -> void:
	hud = config.get("hud")
	building_selection = config.get("building_selection")
	building_upgrade_panel = config.get("building_upgrade_panel")
	card_selection = config.get("card_selection")
	wave_preview = config.get("wave_preview")
	boss_hp_bar = config.get("boss_hp_bar")
	expedition_panel = config.get("expedition_panel")
	result_screen = config.get("result_screen")
	ui_layer = config.get("ui_layer")
	wave_spawner = config.get("wave_spawner")

	# 卡牌选择 UI 信号
	if card_selection and card_selection.has_signal("card_selected"):
		card_selection.card_selected.connect(_on_card_selected)

	# 建筑选择 UI 信号
	if building_selection and building_selection.has_signal("building_selected"):
		building_selection.building_selected.connect(_on_building_selection_made)

	# 出征 UI 信号
	if expedition_panel:
		if expedition_panel.has_signal("expedition_selected"):
			expedition_panel.expedition_selected.connect(_on_expedition_selected)
		if expedition_panel.has_signal("support_requested"):
			expedition_panel.support_requested.connect(_on_support_requested)

	# 结算屏幕信号
	if result_screen:
		if result_screen.has_signal("restart_requested"):
			result_screen.restart_requested.connect(_on_restart_requested)
		if result_screen.has_signal("main_menu_requested"):
			result_screen.main_menu_requested.connect(_on_main_menu_requested)

	# 暂停菜单
	var PauseMenuScene := preload("res://scenes/ui/pause_menu.tscn")
	pause_menu = PauseMenuScene.instantiate()
	if ui_layer:
		ui_layer.add_child(pause_menu)
	if pause_menu.has_signal("resume_requested"):
		pause_menu.resume_requested.connect(_on_pause_resume)
	if pause_menu.has_signal("restart_requested"):
		pause_menu.restart_requested.connect(_on_pause_restart)
	if pause_menu.has_signal("main_menu_requested"):
		pause_menu.main_menu_requested.connect(_on_pause_main_menu)


## 设置卡牌系统引用（GameSession 初始化后调用）
func set_card_system(pool: CardPool, effects: CardEffects) -> void:
	card_pool = pool
	card_effects = effects


## 更新当前英雄引用（英雄切换时调用）
func set_current_hero(hero: HeroBase) -> void:
	current_hero = hero


# ============================================================
# PhaseManager UI 响应
# ============================================================

func on_phase_changed(phase_name: String, expedition_manager: ExpeditionManager) -> void:
	if building_upgrade_panel and building_upgrade_panel.has_method("hide_panel"):
		building_upgrade_panel.hide_panel()
	match phase_name:
		"transition":
			if expedition_panel and expedition_panel.has_method("show_selection"):
				expedition_panel.show_selection(expedition_manager.get_available_expeditions())
		"card_selection":
			_handle_card_selection_phase()
		"boss":
			if wave_spawner and not wave_spawner.enemy_spawned.is_connected(_on_enemy_spawned_for_boss):
				wave_spawner.enemy_spawned.connect(_on_enemy_spawned_for_boss)


func _handle_card_selection_phase() -> void:
	if building_selection and building_selection.has_method("show_selection"):
		building_selection.show_selection(["arrow_tower", "gold_mine", "barracks"])
		if building_selection.is_active:
			await building_selection.building_selected
	_trigger_card_selection()


func on_tutorial_message(text: String) -> void:
	if hud and hud.has_method("show_tutorial_tip"):
		hud.show_tutorial_tip(text)


func on_transition_tick(remaining: float) -> void:
	if hud and hud.has_method("update_wave_info"):
		hud.update_wave_info(0, "出征准备 %.0fs" % maxf(remaining, 0))


func on_countdown_tick(seconds: int) -> void:
	if hud and hud.has_method("show_countdown"):
		hud.show_countdown(seconds)


# ============================================================
# WaveSpawner UI 响应
# ============================================================

func on_wave_started(wave_index: int, wave_label: String) -> void:
	if hud and hud.has_method("update_wave_info"):
		hud.update_wave_info(wave_index + 1, wave_label)
	if wave_preview and wave_preview.has_method("show_preview") and wave_spawner:
		var waves: Array = wave_spawner.current_stage_data.get("waves", [])
		if wave_index < waves.size():
			wave_preview.show_preview(waves[wave_index])


# ============================================================
# 出征 UI
# ============================================================

func on_expedition_started(expedition_id: String, expedition_manager: ExpeditionManager) -> void:
	# 隐藏建筑按钮
	if hud and hud.has_method("set_build_buttons_visible"):
		hud.set_build_buttons_visible(false)

	# 连接倒计时信号 → 底部条
	if expedition_manager.has_signal("expedition_timer_tick"):
		if not expedition_manager.expedition_timer_tick.is_connected(_on_expedition_timer_tick):
			expedition_manager.expedition_timer_tick.connect(_on_expedition_timer_tick)

	var exp_name: String = ""
	for ed: Dictionary in expedition_manager.all_expeditions:
		if ed.get("id", "") == expedition_id:
			exp_name = ed.get("name", "出征中")
			break
	if expedition_panel and expedition_panel.has_method("show_progress"):
		expedition_panel.show_progress(exp_name)
	if expedition_panel and expedition_panel.has_method("show_support_buttons"):
		expedition_panel.show_support_buttons(
			expedition_manager.support_available_types,
			expedition_manager.support_remaining,
			expedition_manager.support_types_config
		)


func on_expedition_phase_changed(phase_index: int, phase_name: String, description: String) -> void:
	if expedition_panel and expedition_panel.has_method("update_phase"):
		expedition_panel.update_phase(phase_index, phase_name, description)


func on_expedition_completed(success: bool, rewards: Dictionary) -> void:
	if expedition_panel and expedition_panel.has_method("show_result"):
		expedition_panel.show_result(success, rewards)


func on_expedition_result_dismissed() -> void:
	if expedition_panel:
		expedition_panel.hide_panel()
	# 恢复建筑按钮
	if hud and hud.has_method("set_build_buttons_visible"):
		hud.set_build_buttons_visible(true)


func _on_expedition_timer_tick(remaining: float, _phase_index: int) -> void:
	if expedition_panel and expedition_panel.has_method("update_timer"):
		expedition_panel.update_timer(remaining)


func on_support_used(remaining: int) -> void:
	if expedition_panel and expedition_panel.has_method("update_support_buttons"):
		expedition_panel.update_support_buttons(remaining)


# ============================================================
# BOSS 血条
# ============================================================

func _on_enemy_spawned_for_boss(enemy: Node2D) -> void:
	if "enemy_id" in enemy and enemy.enemy_id == "demon_boss":
		if boss_hp_bar and boss_hp_bar.has_method("bind_boss"):
			boss_hp_bar.bind_boss(enemy)
		if wave_spawner and wave_spawner.enemy_spawned.is_connected(_on_enemy_spawned_for_boss):
			wave_spawner.enemy_spawned.disconnect(_on_enemy_spawned_for_boss)


# ============================================================
# 结算屏幕
# ============================================================

func show_game_over(victory: bool, stats: Dictionary) -> void:
	if result_screen and result_screen.has_method("show_result"):
		result_screen.show_result(victory, stats)


func _on_restart_requested() -> void:
	if result_screen and result_screen.has_method("hide_result"):
		result_screen.hide_result()
	restart_requested.emit()


func _on_main_menu_requested() -> void:
	if result_screen and result_screen.has_method("hide_result"):
		result_screen.hide_result()
	main_menu_requested.emit()


# ============================================================
# 暂停菜单
# ============================================================

func handle_esc_pause() -> void:
	var state: String = GameManager.game_state
	if state not in ["playing", "defend"]:
		return
	if pause_menu and pause_menu.has_method("show_pause_menu"):
		pause_menu.show_pause_menu()


func _on_pause_resume() -> void:
	pass


func _on_pause_restart() -> void:
	pass


func _on_pause_main_menu() -> void:
	pass


# ============================================================
# 卡牌选择
# ============================================================

func _trigger_card_selection() -> void:
	if card_pool == null or card_selection == null:
		card_selection_done.emit()
		return
	if current_hero == null:
		card_selection_done.emit()
		return

	var hero_id: String = ""
	if current_hero.has_method("get") and current_hero.get("hero_id") != null:
		hero_id = current_hero.hero_id
	elif current_hero.has_meta("hero_id"):
		hero_id = current_hero.get_meta("hero_id")

	var current_wave_val: int = GameManager.current_wave
	var total_waves: int = wave_spawner.get_total_waves() if wave_spawner.has_method("get_total_waves") else 10
	var cards: Array = card_pool.draw_three(current_wave_val, total_waves, hero_id)

	if cards.size() < 3:
		card_selection_done.emit()
		return

	var card_dicts: Array = []
	for card in cards:
		if card is CardData:
			card_dicts.append({
				"id": card.id,
				"name": card.card_name,
				"category": card.category,
				"rarity": card.rarity,
				"icon_color": card.icon_color,
				"source_building": card.source_building,
				"description": card.description,
				"effects": card.effects,
				"hero_filter": card.hero_filter,
			})
		else:
			card_dicts.append(card)

	if card_selection.has_method("show_cards"):
		card_selection.show_cards(card_dicts)


func _on_card_selected(card_data: Dictionary) -> void:
	if current_hero == null:
		card_selection_done.emit()
		return
	if card_effects:
		card_effects.apply_card(card_data, current_hero)
	if card_pool:
		var card_id: String = card_data.get("id", "")
		for card in card_pool.all_cards:
			if card.id == card_id:
				card_pool.record_selection(card)
				break
	card_selection_done.emit()


# ============================================================
# 建筑选择
# ============================================================

func _on_building_selection_made(building_id: String) -> void:
	building_selection_made.emit(building_id)


func _on_expedition_selected(expedition_id: String) -> void:
	if expedition_id == "":
		expedition_skipped.emit()
	else:
		expedition_selected.emit(expedition_id)


func _on_support_requested(support_type: String) -> void:
	support_requested.emit(support_type)


# ============================================================
# 局外加成通知
# ============================================================

func show_meta_bonus_notification() -> void:
	if not is_instance_valid(SaveManager) or hud == null:
		return
	var bonus: Dictionary = SaveManager.get_hero_bonus("wolf_knight")
	var pct: float = bonus.get("attack_pct", 0.0)
	if pct <= 0.0:
		return
	var notification := Label.new()
	notification.text = "局外加成: 全属性 +%.0f%%" % (pct * 100)
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notification.add_theme_font_size_override("font_size", 20)
	notification.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	notification.add_theme_color_override("font_shadow_color", Color.BLACK)
	notification.add_theme_constant_override("shadow_offset_x", 1)
	notification.add_theme_constant_override("shadow_offset_y", 1)
	notification.anchors_preset = Control.PRESET_CENTER_TOP
	notification.offset_top = 50.0
	notification.offset_left = -120.0
	notification.offset_right = 120.0
	hud.add_child(notification)
	var tween := hud.create_tween()
	tween.tween_property(notification, "modulate:a", 0.0, 2.0).set_delay(1.5)
	tween.tween_callback(notification.queue_free)
