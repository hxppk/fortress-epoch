extends SceneTree
## 场景审计脚本 — 扫描所有 .tscn 文件的配置问题
## 用法: godot --headless --script res://scripts/tests/scene_audit.gd

var issues: Array = []
var checked: int = 0


func _init() -> void:
	print("=" .repeat(60))
	print("  场景审计工具 v0.2.1")
	print("=" .repeat(60))

	var scene_paths: Array = _find_all_tscn("res://scenes/")
	print("发现 %d 个 .tscn 文件\n" % scene_paths.size())

	for path: String in scene_paths:
		_audit_scene(path)

	_print_report()
	quit()


func _find_all_tscn(base_path: String) -> Array:
	var results: Array = []
	var dir := DirAccess.open(base_path)
	if dir == null:
		return results

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		var full_path: String = base_path + file_name
		if dir.current_is_dir():
			results.append_array(_find_all_tscn(full_path + "/"))
		elif file_name.ends_with(".tscn"):
			results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	return results


func _audit_scene(path: String) -> void:
	checked += 1
	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		issues.append("[ERROR] 无法加载: %s" % path)
		return

	var state := packed.get_state()
	var node_count: int = state.get_node_count()

	# 检查 z_index 顺序
	var z_indices: Array = []
	for i: int in range(node_count):
		var props: Dictionary = {}
		for p: int in range(state.get_node_property_count(i)):
			var prop_name: String = state.get_node_property_name(i, p)
			props[prop_name] = state.get_node_property_value(i, p)

		if props.has("z_index"):
			z_indices.append({
				"node": state.get_node_name(i),
				"z_index": props["z_index"],
			})

		# 检查 UI 节点的 mouse_filter
		var node_type: String = state.get_node_type(i)
		if node_type in ["Control", "Panel", "Label", "TextureRect", "ColorRect", "HBoxContainer", "VBoxContainer", "MarginContainer", "CenterContainer"]:
			if not props.has("mouse_filter"):
				# 默认 mouse_filter=0 (STOP) 可能会阻挡输入
				if node_type in ["Label", "TextureRect", "ColorRect"]:
					issues.append("[WARN] %s → %s (%s) 未设置 mouse_filter，可能阻挡点击" % [
						path.get_file(), state.get_node_name(i), node_type
					])

	# 检查 z_index 是否有冲突
	if z_indices.size() > 1:
		var seen: Dictionary = {}
		for entry: Dictionary in z_indices:
			var z: int = entry["z_index"]
			if seen.has(z):
				issues.append("[INFO] %s → z_index=%d 重复: %s, %s" % [
					path.get_file(), z, seen[z], entry["node"]
				])
			seen[z] = entry["node"]

	# 检查 CanvasLayer 层级
	for i: int in range(node_count):
		var node_type: String = state.get_node_type(i)
		if node_type == "CanvasLayer":
			var layer_val: int = 0
			for p: int in range(state.get_node_property_count(i)):
				if state.get_node_property_name(i, p) == "layer":
					layer_val = state.get_node_property_value(i, p)
			if layer_val == 0:
				issues.append("[INFO] %s → CanvasLayer '%s' 使用默认 layer=0" % [
					path.get_file(), state.get_node_name(i)
				])


func _print_report() -> void:
	print("\n" + "=" .repeat(60))
	print("  审计结果: %d 个场景, %d 个问题" % [checked, issues.size()])
	print("=" .repeat(60))

	if issues.is_empty():
		print("  全部通过!")
	else:
		for issue: String in issues:
			print("  %s" % issue)

	print("")
