class_name BloodTextures
extends RefCounted
## Procedural decal textures, generated once at startup so the project ships without art assets.
## Shapes are drawn into a float coverage buffer and then tinted: thick blood dark, thin blood bright.

const SIZE := 128
const CENTER := 64.0
const BLOOD_THICK := Color(0.2, 0.0, 0.005)
const BLOOD_THIN := Color(0.5, 0.02, 0.02)


## Round impact splat with spikes and satellite droplets.
static func splat(rng: RandomNumberGenerator) -> ImageTexture:
	var buf := _buffer()
	for i in 10:
		var a := rng.randf() * TAU
		var d := rng.randf() * 14.0
		_stamp(buf, CENTER + cos(a) * d, CENTER + sin(a) * d, rng.randf_range(12.0, 22.0), 3.0)
	for i in 7:
		var a := rng.randf() * TAU
		var reach := rng.randf_range(34.0, 56.0)
		var t := 20.0
		while t < reach:
			_stamp(buf, CENTER + cos(a) * t, CENTER + sin(a) * t, lerpf(5.0, 1.5, (t - 20.0) / (reach - 20.0)), 1.5)
			t += 2.5
	for i in 26:
		var a := rng.randf() * TAU
		var d := rng.randf_range(30.0, 60.0)
		_stamp(buf, CENTER + cos(a) * d, CENTER + sin(a) * d, rng.randf_range(1.2, 4.5), 1.2)
	return _to_texture(buf, BLOOD_THICK, BLOOD_THIN)


## Directional spatter: source at the bottom edge, elongated drops fanning out toward the top.
static func spray(rng: RandomNumberGenerator) -> ImageTexture:
	var buf := _buffer()
	for i in 46:
		var t := rng.randf()
		var x := CENTER + (rng.randf() - 0.5) * (10.0 + t * 76.0)
		var y := 118.0 - t * 108.0
		var radius := rng.randf_range(1.5, 4.2) * (1.0 - 0.4 * t)
		for k in 4:
			_stamp(buf, x, y + k * radius * 0.9, radius * (1.0 - k * 0.2), 1.2)
	for i in 5:
		_stamp(buf, CENTER + rng.randf_range(-6.0, 6.0), 112.0 - i * 5.0, rng.randf_range(5.0, 9.0), 2.5)
	return _to_texture(buf, BLOOD_THICK, BLOOD_THIN)


## Smooth lobed puddle; the decal is scaled up as the pool grows.
static func pool(rng: RandomNumberGenerator) -> ImageTexture:
	var buf := _buffer()
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var p3 := rng.randf() * TAU
	for y in SIZE:
		var dy := y - CENTER
		for x in SIZE:
			var dx := x - CENTER
			var angle := atan2(dy, dx)
			var edge := 48.0 + 6.0 * sin(3.0 * angle + p1) + 4.0 * sin(5.0 * angle + p2) + 2.5 * sin(9.0 * angle + p3)
			buf[y * SIZE + x] = clampf((edge - sqrt(dx * dx + dy * dy)) / 5.0, 0.0, 1.0)
	return _to_texture(buf, Color(0.16, 0.0, 0.0), Color(0.38, 0.01, 0.01))


## Drag streak left by a sliding gib or limb.
static func smear(rng: RandomNumberGenerator) -> ImageTexture:
	var buf := _buffer()
	var x := CENTER
	for i in 38:
		var t := i / 37.0
		x += rng.randf_range(-1.6, 1.6)
		var strength := rng.randf_range(0.45, 1.0) * (1.0 - 0.5 * t)
		_stamp(buf, x, 112.0 - t * 96.0, 3.0 + 9.0 * pow(1.0 - t, 0.6), 4.0, strength)
	for i in 10:
		_stamp(buf, CENTER + rng.randf_range(-14.0, 14.0), rng.randf_range(20.0, 110.0), rng.randf_range(1.0, 3.0), 1.0)
	return _to_texture(buf, BLOOD_THICK, BLOOD_THIN, 0.85)


## Skin wound: dark channel with a ragged bleeding rim.
static func wound(rng: RandomNumberGenerator) -> ImageTexture:
	var buf := _buffer()
	for i in 9:
		var a := rng.randf() * TAU
		_stamp(buf, CENTER + cos(a) * 12.0, CENTER + sin(a) * 12.0, rng.randf_range(10.0, 17.0), 6.0, 0.55)
	_stamp(buf, CENTER, CENTER, 15.0, 4.0)
	for i in 14:
		var a := rng.randf() * TAU
		var d := rng.randf_range(26.0, 50.0)
		_stamp(buf, CENTER + cos(a) * d, CENTER + sin(a) * d, rng.randf_range(1.5, 4.0), 1.5, 0.8)
	return _to_texture(buf, Color(0.05, 0.0, 0.0), Color(0.48, 0.03, 0.03))


static func bullet_hole(rng: RandomNumberGenerator) -> ImageTexture:
	var buf := _buffer()
	_stamp(buf, CENTER, CENTER, 26.0, 16.0, 0.5)
	for i in 6:
		var a := rng.randf() * TAU
		var reach := rng.randf_range(24.0, 46.0)
		var t := 10.0
		while t < reach:
			_stamp(buf, CENTER + cos(a) * t, CENTER + sin(a) * t, 1.4, 1.0, 0.65)
			t += 1.5
	_stamp(buf, CENTER, CENTER, 12.0, 2.5)
	return _to_texture(buf, Color(0.0, 0.0, 0.0), Color(0.16, 0.15, 0.14))


static func scorch(rng: RandomNumberGenerator) -> ImageTexture:
	var buf := _buffer()
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	for y in SIZE:
		var dy := y - CENTER
		for x in SIZE:
			var dx := x - CENTER
			var angle := atan2(dy, dx)
			var edge := 54.0 + 6.0 * sin(7.0 * angle + p1) + 4.0 * sin(13.0 * angle + p2)
			buf[y * SIZE + x] = pow(clampf(1.0 - sqrt(dx * dx + dy * dy) / edge, 0.0, 1.0), 1.4) * 0.62
	return _to_texture(buf, Color(0.0, 0.0, 0.0), Color(0.05, 0.04, 0.03))


static func _buffer() -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(SIZE * SIZE)
	buf.fill(0.0)
	return buf


## Writes a soft disc, keeping the maximum coverage where shapes overlap.
static func _stamp(buf: PackedFloat32Array, cx: float, cy: float, radius: float, softness: float, strength := 1.0) -> void:
	var x0 := maxi(int(cx - radius), 0)
	var x1 := mini(int(cx + radius) + 1, SIZE - 1)
	var y0 := maxi(int(cy - radius), 0)
	var y1 := mini(int(cy + radius) + 1, SIZE - 1)
	for y in range(y0, y1 + 1):
		var dy := y - cy
		var row := y * SIZE
		for x in range(x0, x1 + 1):
			var dx := x - cx
			var a := clampf((radius - sqrt(dx * dx + dy * dy)) / softness, 0.0, 1.0) * strength
			if a > buf[row + x]:
				buf[row + x] = a


static func _to_texture(buf: PackedFloat32Array, thick: Color, thin: Color, opacity := 0.96) -> ImageTexture:
	var bytes := PackedByteArray()
	bytes.resize(SIZE * SIZE * 4)
	for i in SIZE * SIZE:
		var a := buf[i]
		var o := i * 4
		# Fully transparent texels keep the thin colour so mipmaps do not pick up a dark fringe.
		bytes[o] = int(lerpf(thin.r, thick.r, a) * 255.0)
		bytes[o + 1] = int(lerpf(thin.g, thick.g, a) * 255.0)
		bytes[o + 2] = int(lerpf(thin.b, thick.b, a) * 255.0)
		bytes[o + 3] = int(clampf(a * 1.6, 0.0, 1.0) * opacity * 255.0)
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, bytes)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
