class_name CardSelectionUI
extends Control
## 三选一卡牌选择界面主控制器

signal card_selected(card_data: Dictionary)

## 3 个 CardUI 的引用
var card_nodes: Array = []
## 当前展示的 3 张卡牌数据
var current_cards: Array = []
## 是否正在展示
var is_active: bool = false

@onready var card1: PanelContainer = $VBoxContainer/CardsContainer/Card1
@onready var card2: PanelContainer = $VBoxContainer/CardsContainer/Card2
@onready var card3: PanelContainer = $VBoxContainer/CardsContainer/Card3
@onready var dim_overlay: ColorRect = $DimOverlay


func _ready() -> void:
	card_nodes = [card1, card2, card3]
	# 连接每张卡牌的点击信号
	for card_node in card_nodes:
		if card_node and card_node.has_signal("card_clicked"):
			card_node.card_clicked.connect(_on_card_selected)
	# 初始隐藏
	visible = false
	is_active = false


## 传入 3 张卡牌数据，填充 UI，暂停游戏，显示面板
func show_cards(cards: Array) -> void:
	if cards.size() < 3:
		push_warning("[CardSelectionUI] 需要至少 3 张卡牌数据，当前: %d" % cards.size())
		return

	current_cards = cards
	is_active = true

	# 填充 3 张卡牌
	for i in range(3):
		var card_node = card_nodes[i]
		card_node.setup(cards[i])
		# 确保卡牌可见且状态重置
		card_node.modulate = Color.WHITE
		card_node.scale = Vector2.ONE
		card_node.visible = true

	# 暂停时仍可交互
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 显示面板
	visible = true

	# 入场动画 — 从下方滑入 + 淡入
	modulate = Color(1, 1, 1, 0)
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)

	# 卡牌依次弹入
	for i in range(3):
		var card_node = card_nodes[i]
		card_node.scale = Vector2(0.6, 0.6)
		card_node.pivot_offset = card_node.size / 2.0
		var card_tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		card_tween.tween_property(card_node, "scale", Vector2.ONE, 0.35).set_delay(0.05 * i)

	# 暂停游戏
	get_tree().paused = true


## 选中一张卡牌
func _on_card_selected(data: Dictionary) -> void:
	if not is_active:
		return
	is_active = false

	# 找到被选中的卡牌，播放选中动画；其余淡出
	for card_node in card_nodes:
		if card_node.card_data.get("id", "") == data.get("id", ""):
			card_node.play_select_animation()
		else:
			card_node.play_dismiss_animation()

	# 等待 0.5 秒动画完成
	var timer := get_tree().create_timer(0.5, true, false, true)
	await timer.timeout

	# 发出选择完成信号
	card_selected.emit(data)

	# 隐藏面板
	hide_cards()

	# 恢复游戏
	get_tree().paused = false


## 隐藏选择界面
func hide_cards() -> void:
	is_active = false
	var tween := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): visible = false)
