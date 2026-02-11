extends Control
## Minimap — 小地图
## 显示在 HUD 右上角，以缩小比例展示堡垒位置、英雄位置、敌人位置、建筑位置。
## 使用 _draw() 纯代码绘制，不依赖额外资源。

# ============================================================
# 属性
# ============================================================

## 小地图显示范围（世界坐标）
var map_rect: Rect2 = Rect2(-50, -50, 580, 480)

## 小地图 UI 尺寸
var minimap_size: Vector2 = Vector2(120, 90)

## 堡垒位置（世界坐标）
var fortress_pos: Vector2 = Vector2(240, 200)

## 刷新间隔（秒）
var update_interval: float = 0.2

## 刷新计时器
var _update_timer: float = 0.0

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	custom_minimum_size = minimap_size


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		queue_redraw()

# ============================================================
# 绘制
# ============================================================

func _draw() -> void:
	# 背景
	draw_rect(Rect2(Vector2.ZERO, minimap_size), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(Vector2.ZERO, minimap_size), Color(0.5, 0.5, 0.5, 0.5), false, 1.0)

	# 堡垒（金色方块）
	var fort_pos: Vector2 = _world_to_minimap(fortress_pos)
	draw_rect(Rect2(fort_pos - Vector2(3, 3), Vector2(6, 6)), Color.GOLD)

	# 英雄（青色圆点）
	var heroes := get_tree().get_nodes_in_group("heroes")
	for hero: Node2D in heroes:
		var pos: Vector2 = _world_to_minimap(hero.global_position)
		draw_circle(pos, 2.5, Color.CYAN)

	# 敌人（红色小点）
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy: Node2D in enemies:
		if not enemy.visible:
			continue
		var pos: Vector2 = _world_to_minimap(enemy.global_position)
		draw_circle(pos, 1.5, Color.RED)

	# 建筑（绿色方块）
	var buildings := get_tree().get_nodes_in_group("buildings")
	for building: Node2D in buildings:
		var pos: Vector2 = _world_to_minimap(building.global_position)
		draw_rect(Rect2(pos - Vector2(2, 2), Vector2(4, 4)), Color.GREEN)

# ============================================================
# 辅助方法
# ============================================================

## 世界坐标 -> 小地图坐标
func _world_to_minimap(world_pos: Vector2) -> Vector2:
	var relative: Vector2 = (world_pos - map_rect.position) / map_rect.size
	return Vector2(
		clampf(relative.x * minimap_size.x, 0, minimap_size.x),
		clampf(relative.y * minimap_size.y, 0, minimap_size.y)
	)
