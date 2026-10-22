class_name HealthBar
extends RefCounted
## Полоска здоровья над существом или персонажем. Всегда повёрнута к камере.
## Ширина полоски растёт с запасом здоровья, поэтому крепкого зверя видно сразу.
## Доля здоровья передаётся в шейдер (shaders/health_bar.gdshader) через параметр экземпляра.

const SHADER := preload("res://shaders/health_bar.gdshader")

## Новая полоска. max_hp задаёт ширину: 100 здоровья — 1 м.
static func make(max_hp: float, col: Color) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var q := QuadMesh.new()
	q.size = Vector2(clamp(max_hp / 100.0, 0.5, 2.2), 0.13)
	q.material = mat
	var m := MeshInstance3D.new()
	m.mesh = q
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.set_instance_shader_parameter("fill", col)
	return m


static func set_value(bar: MeshInstance3D, hp: float, max_hp: float) -> void:
	bar.set_instance_shader_parameter("frac", clamp(hp / max(max_hp, 1.0), 0.0, 1.0))


static func temper_color(temper: String) -> Color:
	return {"passive": Color("#7fe07a"), "neutral": Color("#ffb040"), "aggressive": Color("#ff4a3a")}.get(temper, Color.WHITE)
