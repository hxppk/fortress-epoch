extends Control
## 游戏内 HUD — 显示资源、血池、波次信息

@onready var gold_label: Label = $TopBar/GoldLabel
@onready var crystal_label: Label = $TopBar/CrystalLabel
@onready var hp_bar: ProgressBar = $TopBar/HPBar
@onready var hp_label: Label = $TopBar/HPBar/HPLabel
@onready var wave_label: Label = $TopBar/WaveLabel
@onready var skill1_bar: ProgressBar = $BottomBar/Skill1Bar
@onready var skill2_bar: ProgressBar = $BottomBar/Skill2Bar
@onready var ultimate_bar: ProgressBar = $BottomBar/UltimateBar


func _ready() -> void:
	GameManager.resource_changed.connect(_on_resource_changed)
	GameManager.shared_hp_changed.connect(_on_hp_changed)
	GameManager.game_over.connect(_on_game_over)

	# 初始化显示
	_on_resource_changed("gold", GameManager.resources.get("gold", 0))
	_on_resource_changed("crystal", GameManager.resources.get("crystal", 0))
	_on_hp_changed(GameManager.shared_hp, GameManager.max_shared_hp)


func _on_resource_changed(type: String, new_amount: int) -> void:
	match type:
		"gold":
			if gold_label:
				gold_label.text = "Gold: %d" % new_amount
		"crystal":
			if crystal_label:
				crystal_label.text = "Crystal: %d" % new_amount


func _on_hp_changed(current: int, maximum: int) -> void:
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current
	if hp_label:
		hp_label.text = "%d / %d" % [current, maximum]


func update_wave_info(wave_number: int, label: String) -> void:
	if wave_label:
		wave_label.text = "Wave %d: %s" % [wave_number, label]


func update_skill_cooldown(slot: int, remaining: float, total: float) -> void:
	var bar: ProgressBar = null
	if slot == 1:
		bar = skill1_bar
	elif slot == 2:
		bar = skill2_bar
	if bar:
		bar.max_value = total
		bar.value = total - remaining


func update_ultimate_charge(current: float, maximum: float) -> void:
	if ultimate_bar:
		ultimate_bar.max_value = maximum
		ultimate_bar.value = current


func _on_game_over(victory: bool) -> void:
	var result_text := "Victory!" if victory else "Defeat..."
	print("[HUD] Game Over: %s" % result_text)
