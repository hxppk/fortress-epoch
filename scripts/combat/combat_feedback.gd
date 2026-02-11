extends Node
## CombatFeedback — 战斗视觉反馈（闪白、屏幕震动、击杀粒子、弹性缩放）
## 可作为 Autoload 使用，也可挂载到场景中。

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
	tween.tween_property(sprite, "scale", original_scale * 1.3, 0.05).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(sprite, "scale", original_scale, 0.1).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BACK)

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
