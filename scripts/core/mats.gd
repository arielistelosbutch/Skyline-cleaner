class_name Mats
extends RefCounted
## Sdílené materiály (jedna instance na typ = méně přepínání stavů GPU).

static var _cache := {}


static func vc() -> StandardMaterial3D:
	if not _cache.has("vc"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.88
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		_cache["vc"] = m
	return _cache["vc"]


## Budovy s domy: jako vc(), ale v zimě se sněhem na šikmých střechách.
static func vc_snow() -> ShaderMaterial:
	if not _cache.has("vc_snow"):
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/building.gdshader")
		_cache["vc_snow"] = m
	return _cache["vc_snow"]


static func vc_glossy() -> StandardMaterial3D:
	if not _cache.has("vc_glossy"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.25
		m.metallic = 0.15
		_cache["vc_glossy"] = m
	return _cache["vc_glossy"]


const NIGHT_GLASS := preload("res://shaders/glass_night.gdshader")


## Sklo dekorativních (neomyvatelných) oken – v noci se část rozsvítí.
static func glass_static() -> ShaderMaterial:
	if not _cache.has("glass_static"):
		var m := ShaderMaterial.new()
		m.shader = NIGHT_GLASS
		m.set_shader_parameter("base_color", Color(0.32, 0.42, 0.46, 0.55))
		m.set_shader_parameter("metallic", 0.1)
		m.set_shader_parameter("roughness", 0.08)
		_cache["glass_static"] = m
	return _cache["glass_static"]


## Zrcadlové sklo mrakodrapů (barva z vertexů) – odráží nebe a budovy kolem,
## v noci svítí náhodná okna po patrech.
static func mirror_glass() -> ShaderMaterial:
	if not _cache.has("mirror_glass"):
		var m := ShaderMaterial.new()
		m.shader = NIGHT_GLASS
		m.set_shader_parameter("use_vertex_color", true)
		m.set_shader_parameter("transparent", false)
		m.set_shader_parameter("per_node", false)
		m.set_shader_parameter("metallic", 0.9)
		m.set_shader_parameter("metallic_specular", 0.7)
		m.set_shader_parameter("roughness", 0.06)
		_cache["mirror_glass"] = m
	return _cache["mirror_glass"]


## Neprůhledné okenní pásy fasád (barva z vertexů), v noci svítí po patrech.
static func facade_glass() -> ShaderMaterial:
	if not _cache.has("facade_glass"):
		var m := ShaderMaterial.new()
		m.shader = NIGHT_GLASS
		m.set_shader_parameter("use_vertex_color", true)
		m.set_shader_parameter("transparent", false)
		m.set_shader_parameter("per_node", false)
		m.set_shader_parameter("metallic", 0.0)
		m.set_shader_parameter("metallic_specular", 0.5)
		m.set_shader_parameter("roughness", 0.88)
		_cache["facade_glass"] = m
	return _cache["facade_glass"]


static func car_glass() -> StandardMaterial3D:
	if not _cache.has("car_glass"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.15, 0.2, 0.24)
		m.roughness = 0.06
		m.metallic = 0.3
		_cache["car_glass"] = m
	return _cache["car_glass"]


static func water() -> StandardMaterial3D:
	if not _cache.has("water"):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.25, 0.5, 0.58, 0.82)
		m.roughness = 0.04
		m.metallic = 0.2
		_cache["water"] = m
	return _cache["water"]


static func ghost(valid: bool) -> StandardMaterial3D:
	var key := "ghost_ok" if valid else "ghost_bad"
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.4, 1.0, 0.6, 0.35) if valid else Color(1.0, 0.4, 0.35, 0.35)
		m.no_depth_test = false
		_cache[key] = m
	return _cache[key]


static func sparkle() -> StandardMaterial3D:
	if not _cache.has("sparkle"):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_color = Color(1.0, 0.97, 0.85, 0.9)
		m.albedo_texture = _star_texture()
		_cache["sparkle"] = m
	return _cache["sparkle"]


static func particle(color: Color) -> StandardMaterial3D:
	var key := "particle_%s" % color.to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_color = color
		m.albedo_texture = _soft_dot_texture()
		_cache[key] = m
	return _cache[key]


static func _star_texture() -> ImageTexture:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var dx := absf(x - s * 0.5 + 0.5) / (s * 0.5)
			var dy := absf(y - s * 0.5 + 0.5) / (s * 0.5)
			var cross := maxf(0.0, 1.0 - dx * 6.0) * maxf(0.0, 1.0 - dy) + maxf(0.0, 1.0 - dy * 6.0) * maxf(0.0, 1.0 - dx)
			var core := maxf(0.0, 1.0 - sqrt(dx * dx + dy * dy) * 2.5)
			var a := clampf(cross * 0.9 + core, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


static func _soft_dot_texture() -> ImageTexture:
	if _cache.has("soft_dot"):
		return _cache["soft_dot"]
	var s := 16
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s * 0.5 + 0.5, y - s * 0.5 + 0.5).length() / (s * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	var t := ImageTexture.create_from_image(img)
	_cache["soft_dot"] = t
	return t
