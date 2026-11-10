class_name StumpCap
extends Node3D
## Cross-section cap for a severed joint. A small procedural shader draws skin, fat, muscle
## bundles, severed vessels, the bone ring and marrow; a short bone stub protrudes from the centre.

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled;

uniform float radius = 0.05;
uniform float variation = 0.0;
varying vec3 local;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + variation) * 43758.5453);
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 p = local.xz / radius;
	float r = length(p);
	float angle = atan(p.y, p.x);
	// Muscle bundles: one tone per angular/radial cell.
	float bundle = hash(vec2(floor(angle * 5.0), floor(r * 6.0)));
	vec3 col = mix(vec3(0.33, 0.02, 0.02), vec3(0.6, 0.07, 0.06), bundle);
	col = mix(col, vec3(0.85, 0.72, 0.42), smoothstep(0.84, 0.88, r));
	col = mix(col, vec3(0.45, 0.1, 0.08), smoothstep(0.94, 0.97, r));
	col = mix(col, vec3(0.9, 0.86, 0.75), 1.0 - smoothstep(0.26, 0.29, r));
	col = mix(col, vec3(0.42, 0.05, 0.07), 1.0 - smoothstep(0.13, 0.16, r));
	// Severed vessels: dark lumen inside a pale wall.
	for (int i = 0; i < 3; i++) {
		float a = hash(vec2(float(i), 7.0)) * 6.2831;
		vec2 c = vec2(cos(a), sin(a)) * (0.5 + 0.2 * hash(vec2(float(i), 3.0)));
		float d = length(p - c);
		col = mix(col, vec3(0.75, 0.55, 0.5), 1.0 - smoothstep(0.07, 0.09, d));
		col = mix(col, vec3(0.12, 0.0, 0.0), 1.0 - smoothstep(0.035, 0.05, d));
	}
	ALBEDO = col;
	ROUGHNESS = 0.22;
	SPECULAR = 0.6;
}
"""

static var _shader: Shader
static var _bone_material: StandardMaterial3D


## `outward` points away from the part the cap is attached to, toward what was cut off.
static func attach(bone: Node3D, position: Vector3, outward: Vector3, radius: float) -> StumpCap:
	var cap := StumpCap.new()
	cap._build(radius)
	bone.add_child(cap)
	var y := outward.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	cap.global_transform = Transform3D(Basis(x, y, x.cross(y)), position)
	return cap


func _build(radius: float) -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
		_bone_material = StandardMaterial3D.new()
		_bone_material.albedo_color = Color(0.86, 0.78, 0.68)
		_bone_material.roughness = 0.5

	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = radius
	disc_mesh.bottom_radius = radius * 0.95
	disc_mesh.height = 0.014
	disc_mesh.radial_segments = 20
	disc_mesh.rings = 1
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("variation", randf() * 50.0)
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh
	disc.material_override = material
	add_child(disc)

	var stub_mesh := CylinderMesh.new()
	stub_mesh.top_radius = radius * 0.2
	stub_mesh.bottom_radius = radius * 0.24
	stub_mesh.height = 0.04
	stub_mesh.radial_segments = 8
	stub_mesh.rings = 1
	var stub := MeshInstance3D.new()
	stub.mesh = stub_mesh
	stub.material_override = _bone_material
	stub.position.y = 0.02
	add_child(stub)
