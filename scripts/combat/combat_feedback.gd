extends Node
## CombatFeedback — 战斗视觉反馈（闪白、屏幕震动、击杀粒子、弹性缩放、帧冻结、连杀）
## 可作为 Autoload 使用，也可挂载到场景中。

# 音效
var _hit_player: AudioStreamPlayer = null
var _click_player: AudioStreamPlayer = null

# 帧冻结状态
var _hitstop_active: bool = false
var _hitstop_timer: float = 0.0

# 连杀系统
var _kill_streak: int = 0
var _kill_streak_timer: float = 0.0
const KILL_STREAK_TIMEOUT: float = 3.0  # 3 秒无击杀重置连杀


func _ready() -> void:
	# 击中音效
	_hit_player = AudioStreamPlayer.new()
	var hit_stream = load("res://assets/audio/hit_004.ogg")
	if hit_stream:
		_hit_player.stream = hit_stream
		_hit_player.volume_db = -5.0
	add_child(_hit_player)

	# UI 点击音效
	_click_player = AudioStreamPlayer.new()
	var click_stream = load("res://assets/audio/click_005.ogg")
	if click_stream:
		_click_player.stream = click_stream
		_click_player.volume_db = -3.0
	add_child(_click_player)

# ============================================================
# 闪白效果
# ============================================================

## 让 sprite 短暂变为纯白，然后恢复
func flash_white(sprite: Node2D, duration: float = 0.1) -> void:
	if not is_instance_valid(sprite):
		return

	# 使用 ShaderMaterial 实现闪白；如果 sprite 尚未挂载着色器则动态创建
	var mat: ShaderMaterial = _ensure_flash_shader(sprite)
	mat.set_shader_parameter("flash_amount", 1.0)

	var tween := sprite.create_tween()
	tween.tween_property(mat, "shader_parameter/flash_amount", 0.0, duration)

# ============================================================
# 屏幕震动
# ============================================================

## 摄像机微震
func screen_shake(camera: Camera2D, intensity: float = 2.0, duration: float = 0.15) -> void:
	if not is_instance_valid(camera):
		return

	var original_offset: Vector2 = camera.offset
	var tween := camera.create_tween()
	var steps: int = 6  # 震动帧数
	var step_duration: float = duration / float(steps)

	for i in steps:
		var random_offset := Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity),
		)
		tween.tween_property(camera, "offset", original_offset + random_offset, step_duration)

	# 最后恢复原位
	tween.tween_property(camera, "offset", original_offset, step_duration)

# ============================================================
# 击杀粒子爆散
# ============================================================

## 在指定位置生成一次性粒子爆散效果
func spawn_death_particles(position: Vector2, color: Color = Color.WHITE) -> void:
	var particles := GPUParticles2D.new()
	particles.position = position
	particles.z_index = 90
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 12
	particles.lifetime = 0.6
	particles.explosiveness = 1.0

	# 创建 ParticleProcessMaterial
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 40.0
	mat.initial_velocity_max = 80.0
	mat.gravity = Vector3(0, 120, 0)
	mat.scale_min = 1.5
	mat.scale_max = 3.0
	mat.color = color

	particles.process_material = mat

	# 添加到场景树
	var tree := get_tree()
	if tree and tree.current_scene:
		tree.current_scene.add_child(particles)
	else:
		add_child(particles)

	# 粒子播放完毕后自动销毁
	var timer := get_tree().create_timer(particles.lifetime + 0.1)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free()
	)

# ============================================================
# 攻击弹性缩放
# ============================================================

## 攻击时 sprite 快速放大再弹回：1.0 -> 1.3 -> 1.0
func hit_scale_effect(sprite: Node2D) -> void:
	if not is_instance_valid(sprite):
		return

	var original_scale: Vector2 = sprite.scale
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "scale", original_scale * 1.8, 0.06).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(sprite, "scale", original_scale, 0.12).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BACK)

# ============================================================
# 音效播放
# ============================================================

## 播放敌人被击中音效
func play_hit_sound() -> void:
	if _hit_player and _hit_player.stream:
		_hit_player.play()


## 播放 UI 点击/悬停音效
func play_click_sound() -> void:
	if _click_player and _click_player.stream:
		_click_player.play()

# ============================================================
# 红色闪屏（敌人入侵堡垒）
# ============================================================

## 全屏红色闪烁警告
func screen_red_flash() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return

	# 创建全屏红色遮罩
	var overlay := ColorRect.new()
	overlay.color = Color(1.0, 0.0, 0.0, 0.35)
	overlay.z_index = 200
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 全屏覆盖 — 放在 CanvasLayer 中确保覆盖整个视口
	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 100
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	canvas_layer.add_child(overlay)
	tree.current_scene.add_child(canvas_layer)

	# 0.25 秒淡出后销毁
	var tween := overlay.create_tween()
	tween.tween_property(overlay, "color:a", 0.0, 0.25)
	tween.tween_callback(canvas_layer.queue_free)

## 堡垒受击闪红
func fortress_flash() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var fortress_visual := tree.current_scene.get_node_or_null("Map/FortressCore/FortressVisual") as ColorRect
	if fortress_visual == null:
		return
	var original_color: Color = Color(0.8, 0.65, 0.2, 1.0)
	fortress_visual.color = Color(1.0, 0.2, 0.2, 1.0)
	var tween := fortress_visual.create_tween()
	tween.tween_property(fortress_visual, "color", original_color, 0.3)

# ============================================================
# 内部工具
# ============================================================

## 闪白着色器源码（嵌入脚本内，无需外部 .gdshader 文件）
const FLASH_SHADER_CODE: String = """
shader_type canvas_item;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	tex.rgb = mix(tex.rgb, vec3(1.0), flash_amount);
	COLOR = tex;
}
"""


# ============================================================
# 帧冻结（Hitstop）
# ============================================================

## 帧冻结：短暂将 Engine.time_scale 设为 0，模拟打击感停顿
## duration_frames: 停顿帧数（按 60fps 换算）
func hitstop(duration_frames: int = 2) -> void:
	if _hitstop_active:
		return  # 避免叠加
	if duration_frames <= 0:
		return

	var duration_seconds: float = float(duration_frames) / 60.0
	_hitstop_active = true
	_hitstop_timer = duration_seconds
	Engine.time_scale = 0.05  # 接近冻结但不完全为0（避免 delta=0 问题）


func _process(delta: float) -> void:
	# 帧冻结恢复（使用未缩放的时间）
	if _hitstop_active:
		_hitstop_timer -= delta / maxf(Engine.time_scale, 0.01)
		if _hitstop_timer <= 0.0:
			_hitstop_active = false
			Engine.time_scale = 1.0

	# 连杀超时检查
	if _kill_streak > 0:
		_kill_streak_timer -= delta
		if _kill_streak_timer <= 0.0:
			_kill_streak = 0

# ============================================================
# 连杀系统
# ============================================================

## 记录一次击杀，更新连杀计数并触发反馈
func record_kill() -> void:
	_kill_streak += 1
	_kill_streak_timer = KILL_STREAK_TIMEOUT

	# 根据连杀数触发不同等级的反馈
	match _kill_streak:
		5:
			_show_kill_streak_text("连杀 x5", Color.WHITE, 24)
		10:
			_show_kill_streak_text("大杀特杀!", Color(0.4, 0.7, 1.0), 28)
		20:
			_show_kill_streak_text("势不可挡!", Color(0.7, 0.4, 1.0), 32)
		50:
			_show_kill_streak_text("无人能挡!", Color.GOLD, 36)
		100:
			_show_kill_streak_text("神一般的割草!", Color(1.0, 0.4, 0.8), 40)
		_:
			# 每 5 连杀也显示一次
			if _kill_streak > 5 and _kill_streak % 5 == 0:
				_show_kill_streak_text("连杀 x%d" % _kill_streak, Color.WHITE, 24)


## 获取当前连杀数
func get_kill_streak() -> int:
	return _kill_streak


## 显示连杀文字（屏幕右下角弹出）
func _show_kill_streak_text(text: String, color: Color, font_size: int) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.z_index = 150

	# 使用 CanvasLayer 确保在 UI 层级
	var canvas := CanvasLayer.new()
	canvas.layer = 90
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.offset_left = -250.0
	label.offset_top = -80.0
	label.offset_right = -20.0
	label.offset_bottom = -40.0
	canvas.add_child(label)
	tree.current_scene.add_child(canvas)

	# 从下方弹入 + 放大 + 缩小 + 淡出
	label.scale = Vector2(0.5, 0.5)
	label.pivot_offset = label.size / 2.0
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_interval(1.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(canvas.queue_free)

# ============================================================
# 击退视觉
# ============================================================

## 对被击中的敌人施加短距离击退效果
func knockback_visual(target: Node2D, from_position: Vector2, distance: float = 5.0, duration: float = 0.1) -> void:
	if not is_instance_valid(target):
		return
	var direction: Vector2 = (target.global_position - from_position).normalized()
	# 添加小幅随机角度偏移
	direction = direction.rotated(randf_range(-0.26, 0.26))  # +/- 15 degrees
	var knockback_offset: Vector2 = direction * distance
	var original_pos: Vector2 = target.global_position
	var tween := target.create_tween()
	tween.tween_property(target, "global_position", original_pos + knockback_offset, duration * 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(target, "global_position", original_pos, duration * 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

# ============================================================
# 改进的屏幕震动（指数衰减）
# ============================================================

## 带衰减曲线的屏幕震动
func screen_shake_decay(camera: Camera2D, intensity: float = 3.0, duration: float = 0.2) -> void:
	if not is_instance_valid(camera):
		return
	var original_offset: Vector2 = camera.offset
	var steps: int = 8
	var step_duration: float = duration / float(steps)
	var tween := camera.create_tween()
	for i in steps:
		var decay: float = pow(1.0 - float(i) / float(steps), 2.0)  # 指数衰减
		var random_offset := Vector2(
			randf_range(-intensity, intensity) * decay,
			randf_range(-intensity, intensity) * decay,
		)
		tween.tween_property(camera, "offset", original_offset + random_offset, step_duration)
	tween.tween_property(camera, "offset", original_offset, step_duration * 0.5)

# ============================================================
# 内部工具
# ============================================================

## 确保 sprite 挂载了闪白着色器，返回其 ShaderMaterial
func _ensure_flash_shader(sprite: Node2D) -> ShaderMaterial:
	# 如果已经有 ShaderMaterial 且包含 flash_amount 参数，直接复用
	if sprite.material is ShaderMaterial:
		var existing_mat: ShaderMaterial = sprite.material as ShaderMaterial
		if existing_mat.shader and existing_mat.get_shader_parameter("flash_amount") != null:
			return existing_mat

	# 新建着色器材质
	var shader := Shader.new()
	shader.code = FLASH_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("flash_amount", 0.0)
	sprite.material = mat
	return mat
