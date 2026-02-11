extends Node
## BuildingInteract — 检测玩家点击建筑的交互逻辑
## 挂载到 GameSession 或 TowerPlacement 同级节点上。
## 通过物理查询检测鼠标位置的建筑碰撞体，筛选 collision_layer 3（buildings, 即 bit 2 = layer 值 4）。

# ============================================================
# 信号
# ============================================================

signal building_clicked(building: Node)

# ============================================================
# 常量
# ============================================================

## 建筑碰撞层 — 在 arrow_tower.tscn 中 collision_layer = 4（即 bit 2，第 3 层）
const BUILDING_COLLISION_LAYER: int = 4

# ============================================================
# 属性
# ============================================================

## 升级面板引用（在 _ready 中查找）
var _upgrade_panel: BuildingUpgradeUI = null

## TowerPlacement 引用（检查放置模式）
var _tower_placement: TowerPlacement = null

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	# 延迟一帧查找节点引用，确保场景树构建完毕
	call_deferred("_find_references")


func _find_references() -> void:
	# 查找升级面板
	_upgrade_panel = _find_node_of_type(get_tree().root, "BuildingUpgradeUI") as BuildingUpgradeUI

	# 查找 TowerPlacement
	_tower_placement = _find_node_of_type(get_tree().root, "TowerPlacement") as TowerPlacement

	# 如果找到了升级面板，连接点击信号
	if _upgrade_panel != null:
		building_clicked.connect(_upgrade_panel.show_panel)
	else:
		push_warning("BuildingInteract: 未找到 BuildingUpgradeUI 节点")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			# 如果处于放置模式，不处理点击
			if _tower_placement != null and _tower_placement.is_placing:
				return

			# 如果升级面板正在显示，不处理（让面板自己处理关闭）
			if _upgrade_panel != null and _upgrade_panel.is_visible_panel:
				return

			var building: Node = _get_building_at_mouse()
			if building != null:
				building_clicked.emit(building)
				get_viewport().set_input_as_handled()

# ============================================================
# 私有方法
# ============================================================

## 用物理查询检测鼠标位置的建筑
func _get_building_at_mouse() -> Node:
	# 获取当前视口和 2D 世界
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null

	var space_state: PhysicsDirectSpaceState2D = viewport.world_2d.direct_space_state
	if space_state == null:
		return null

	# 获取鼠标在世界中的位置
	var mouse_pos: Vector2 = viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()

	# 构建点查询参数
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = mouse_pos
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = BUILDING_COLLISION_LAYER  # 只检测建筑层

	# 执行查询
	var results: Array[Dictionary] = space_state.intersect_point(query, 8)

	# 筛选出 BuildingBase 且已放置的建筑
	for result: Dictionary in results:
		var collider: Object = result.get("collider", null)
		if collider is BuildingBase:
			var building: BuildingBase = collider as BuildingBase
			if building.is_placed:
				return building

	return null


## 递归查找场景树中指定 class_name 的节点
func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node

	# 检查脚本类名
	var script: Script = node.get_script() as Script
	if script != null:
		var script_name: String = _get_script_class_name(script)
		if script_name == type_name:
			return node

	for child: Node in node.get_children():
		var found: Node = _find_node_of_type(child, type_name)
		if found != null:
			return found

	return null


## 获取脚本的 class_name
func _get_script_class_name(script: Script) -> String:
	if script == null:
		return ""
	# GDScript 可以通过 get_global_name() 获取 class_name
	var global_name: String = script.get_global_name()
	if global_name != "":
		return global_name
	return ""
