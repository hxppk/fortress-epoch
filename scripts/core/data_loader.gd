class_name DataLoader
extends RefCounted
## DataLoader — 统一数据加载工具
## 提供带缓存的 JSON 加载，避免重复读取文件。

# ============================================================
# 缓存
# ============================================================

static var _cache: Dictionary = {}

# ============================================================
# 公共接口
# ============================================================

## 加载 JSON 文件并返回解析后的数据，带缓存。
## 加载失败时返回 null 并 push_error。
static func load_json(path: String) -> Variant:
	if _cache.has(path):
		return _cache[path]

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataLoader: 无法打开文件 '%s' (错误: %s)" % [path, error_string(FileAccess.get_open_error())])
		return null

	var json_text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var err: Error = json.parse(json_text)
	if err != OK:
		push_error("DataLoader: JSON 解析失败 '%s' (行 %d: %s)" % [path, json.get_error_line(), json.get_error_message()])
		return null

	_cache[path] = json.data
	return json.data


## 清除所有缓存
static func clear_cache() -> void:
	_cache.clear()
