class_name FragGrenade
extends WeaponBase3D
## M67-type fragmentation grenade as a held weapon.
##
## Hold fire to pull the pin; the hand keeps the safety lever (spoon) down, so nothing burns
## yet. Releasing fire throws the grenade, the spoon flies off and the fuse starts. Pressing aim
## while the pin is out lets the spoon go in the hand to cook the fuse before the throw; hold it
## too long and it detonates where you stand. The thrown body is a GrenadeProjectile.

enum Stage { SAFE, PIN_PULLED, COOKING }

@export var throw_speed := 16.0
@export var fuse_min := 3.5
@export var fuse_max := 4.0
@export var draw_time := 0.8

var stage := Stage.SAFE

var _fuse_left := 0.0
var _pin: Node3D
var _spoon: Node3D


func _init() -> void:
	display_name = "M67 Frag Grenade"
	weapon_id = &"grenade"
	fire_mode = FireMode.SEMI
	magazine_size = 1
	reserve_ammo = 7
	reload_time = draw_time
	can_aim = false
	hip_offset = Vector3(0.17, -0.13, -0.32)
	sound = &"click"


func _setup() -> void:
	_pin = model.get_node(^"Pin")
	_spoon = model.get_node(^"Spoon")


func _physics_process(delta: float) -> void:
	super(delta)
	model.visible = ammo > 0 and not is_reloading
	if stage == Stage.COOKING:
		_fuse_left -= delta
		if _fuse_left <= 0.0:
			_detonate_in_hand()


func trigger_pressed() -> void:
	if stage != Stage.SAFE or is_reloading or wielder == null:
		return
	if ammo <= 0:
		reload()
		return
	stage = Stage.PIN_PULLED
	_pin.visible = false
	Sfx.play(&"click", global_position, -2.0)


func secondary_pressed() -> void:
	if stage != Stage.PIN_PULLED:
		return
	stage = Stage.COOKING
	_fuse_left = randf_range(fuse_min, fuse_max)
	_spoon.visible = false
	Sfx.play(&"pump", global_position, -6.0, 1.6)


func trigger_released() -> void:
	if stage == Stage.SAFE:
		return
	var aim: Transform3D = wielder.get_aim_transform()
	var grenade := GrenadeProjectile.create(wielder)
	wielder.get_tree().current_scene.add_child(grenade)
	grenade.global_position = aim.origin - aim.basis.z * 0.5 + aim.basis.x * 0.15
	var carried := Vector3.ZERO
	if "velocity" in wielder:
		carried = wielder.get("velocity")
	grenade.linear_velocity = (-aim.basis.z + Vector3.UP * 0.18).normalized() * throw_speed + carried
	grenade.angular_velocity = aim.basis.x * -9.0
	# A cooked grenade keeps whatever is left of its fuse; otherwise the fuse starts now.
	grenade.release_spoon(_fuse_left if stage == Stage.COOKING else randf_range(fuse_min, fuse_max))
	_spend()
	fired.emit()


func unequip() -> void:
	# Putting a live grenade away is not an option: it leaves the hand first.
	if stage != Stage.SAFE and wielder != null:
		trigger_released()
	super()


func hud_hint() -> String:
	match stage:
		Stage.PIN_PULLED:
			return "Pin pulled - release LMB to throw   RMB let the spoon go (cook)"
		Stage.COOKING:
			return "COOKING %.1fs - release LMB to throw!" % maxf(_fuse_left, 0.0)
	return "Hold LMB to pull the pin"


func _detonate_in_hand() -> void:
	var aim: Transform3D = wielder.get_aim_transform()
	var grenade := GrenadeProjectile.create(wielder)
	wielder.get_tree().current_scene.add_child(grenade)
	grenade.global_position = aim.origin - aim.basis.z * 0.4
	grenade.explode()
	_spend()


func _spend() -> void:
	stage = Stage.SAFE
	ammo -= 1
	_pin.visible = true
	_spoon.visible = true
	ammo_changed.emit()
	reload()
