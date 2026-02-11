extends Control
## BossHPBar — BOSS 血条 UI
## 屏幕顶部居中的大血条，显示 BOSS 名字和血量。
## 通过 bind_boss() 绑定到 BOSS 的 StatsComponent，自动同步血量变化。

# ============================================================
# 子节点引用
# ============================================================

@onready var _name_label: Label = $VBox/NameLabel
@onready var _hp_bar: ProgressBar = $VBox/HPBar
@onready var _hp_label: Label = $VBox/HPBar/HPLabel

# ============================================================
# 内部状态
# ============================================================

var _boss: Node2D = null
var _boss_stats: StatsComponent = null

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	visible = false

# ============================================================
# 公开方法
# ============================================================

## 绑定到 BOSS 的 StatsComponent
func bind_boss(boss_node: Node2D) -> void:
	_boss = boss_node
	var stats: StatsComponent = boss_node.get_node_or_null("StatsComponent")
	if stats:
		_boss_stats = stats
		stats.health_changed.connect(_on_boss_hp_changed)
		stats.died.connect(_on_boss_died)
		_name_label.text = _get_boss_name(boss_node)
		_hp_bar.max_value = stats.get_stat("hp")
		_hp_bar.value = stats.current_hp
		_hp_label.text = "%d / %d" % [int(stats.current_hp), int(stats.get_stat("hp"))]
		_hp_bar.modulate = Color.WHITE
		modulate.a = 1.0
		visible = true


## 解除绑定
func unbind_boss() -> void:
	if _boss_stats:
		if _boss_stats.health_changed.is_connected(_on_boss_hp_changed):
			_boss_stats.health_changed.disconnect(_on_boss_hp_changed)
		if _boss_stats.died.is_connected(_on_boss_died):
			_boss_stats.died.disconnect(_on_boss_died)
	_boss = null
	_boss_stats = null
	visible = false

# ============================================================
# 信号回调
# ============================================================

## 血量变化回调（StatsComponent 信号参数为 float）
func _on_boss_hp_changed(current: float, maximum: float) -> void:
	_hp_bar.max_value = maximum
	_hp_bar.value = current
	_hp_label.text = "%d / %d" % [int(current), int(maximum)]
	# 低血量变红
	if current / maxf(maximum, 1.0) < 0.3:
		_hp_bar.modulate = Color.RED
	else:
		_hp_bar.modulate = Color.WHITE


## BOSS 死亡回调
func _on_boss_died() -> void:
	# 播放消失动画
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func():
		visible = false
		unbind_boss()
	)

# ============================================================
# 辅助方法
# ============================================================

## 获取 BOSS 显示名字
func _get_boss_name(boss: Node2D) -> String:
	if boss.has_meta("display_name"):
		return boss.get_meta("display_name")
	if "enemy_id" in boss:
		match boss.enemy_id:
			"demon_boss": return "恶魔领主"
			"orc_elite": return "兽人精英"
			_: return boss.enemy_id
	return "BOSS"
