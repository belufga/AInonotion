class_name NPCBrain
extends Node
## Behaviour state machine for a humanoid NPC.
##
## It never moves bones itself: each tick it picks an animation pose and sets the active
## ragdoll's motor strength, balance strength, hip height and travel velocity. Trauma arrives as
## events (hits, blast, loss of consciousness, crippled legs) and moves the machine between
## upright behaviour, stumbling, cowering, crawling and full passive ragdoll.

enum State { IDLE, WANDER, AIM, STUMBLE, COWER, CRAWL, RAGDOLL, GET_UP, DEAD }

signal state_changed(state: State, previous: State)

const UPRIGHT := [State.IDLE, State.WANDER, State.AIM, State.STUMBLE, State.COWER]
const TURN_RATE := 3.5  ## rad/s
const STAND_CLEARANCE := 0.012  ## Soles hover just clear of the floor so standing feet do not load the ankles.
const REACTION_WINDOW := 0.15  ## s; hits closer together than this add up to one impact.

@export var wanders := true
@export var walk_speed := 1.3
@export var crawl_speed := 0.35
@export var alert_range := 30.0

var state := State.IDLE
var humanoid: Humanoid
var has_threat := false
var threat_position := Vector3.ZERO

var _timer := 0.0
var _state_time := 0.0
var _home := Vector3.ZERO
var _destination := Vector3.ZERO
var _fallen_time := 0.0
var _air_time := 0.0
var _held := false
var _stagger := Vector3.ZERO
var _impact_frame := 0
var _impact_energy := 0.0
var _impact_torso_energy := 0.0


func setup(p_humanoid: Humanoid) -> void:
	humanoid = p_humanoid
	_home = humanoid.global_position
	_timer = randf_range(1.5, 4.0)
	process_physics_priority = -1  # Decide before the ragdoll controller acts on the decision.
	humanoid.vitals.consciousness_changed.connect(_on_consciousness_changed)
	humanoid.gore.gibbed.connect(func() -> void: _enter(State.DEAD))


func _physics_process(delta: float) -> void:
	if humanoid == null:
		return
	_state_time += delta
	var ragdoll := humanoid.ragdoll
	var animator := humanoid.animator
	var vitals := humanoid.vitals
	var legs := humanoid.leg_support()
	var stunned := vitals.consciousness == VitalsComponent.Consciousness.STUNNED
	var motor := 1.0
	var balance := 1.0
	var height := Anatomy.STAND_HEIGHT + STAND_CLEARANCE
	var aim := 0.0
	ragdoll.move_velocity = Vector3.ZERO
	ragdoll.support = legs
	ragdoll.drive_strength = 1.0
	animator.speed = 0.0
	animator.tremble = 0.0
	animator.pose = ProceduralAnimator.Pose.STAND

	if state in UPRIGHT:
		if legs < 0.6:
			_enter(State.CRAWL)
		elif _has_fallen(delta):
			knock_down(2.0)

	match state:
		State.IDLE:
			_timer -= delta
			if vitals.pain > 0.6 or stunned:
				_enter(State.COWER)
			elif humanoid.is_armed() and has_threat:
				_enter(State.AIM)
			elif wanders and _timer <= 0.0:
				_destination = _home + Vector3(randf_range(-5.0, 5.0), 0.0, randf_range(-5.0, 5.0))
				_enter(State.WANDER)
		State.WANDER:
			var to := _destination - ragdoll.hips_position()
			to.y = 0.0
			if to.length() < 0.6 or _state_time > 9.0:
				_enter(State.IDLE)
			else:
				_face(to, delta)
				var forward := _forward()
				if forward.dot(to.normalized()) > 0.5:
					ragdoll.move_velocity = forward * walk_speed * (0.5 + 0.5 * vitals.stamina)
				animator.speed = maxf(ragdoll.hips_velocity().dot(forward), 0.0)
		State.AIM:
			aim = 1.0
			var to := threat_position - ragdoll.hips_position()
			to.y = 0.0
			_face(to, delta)
			animator.aim_target = threat_position
			_timer -= delta
			if not humanoid.is_armed() or _timer <= 0.0:
				has_threat = false
				_enter(State.IDLE)
		State.STUMBLE:
			motor = 0.55
			balance = 0.5
			height = 0.94
			ragdoll.move_velocity = _stagger
			animator.speed = 0.8
			_timer -= delta
			if _timer <= 0.0:
				_enter(State.COWER if (vitals.pain > 0.45 or not humanoid.is_armed()) else State.IDLE)
		State.COWER:
			animator.pose = ProceduralAnimator.Pose.COWER
			animator.tremble = 1.0
			height = 0.46
			motor = 0.9
			if _state_time > 6.0 and vitals.pain < 0.35 and vitals.consciousness == VitalsComponent.Consciousness.AWAKE:
				_enter(State.IDLE)
		State.CRAWL:
			animator.pose = ProceduralAnimator.Pose.CRAWL
			height = 0.24
			balance = 0.55
			motor = 0.85
			ragdoll.support = 0.35  # Arms and torso prop the body up, not the legs.
			if vitals.is_conscious():
				var away := ragdoll.hips_position() - threat_position if has_threat else _home - ragdoll.hips_position()
				away.y = 0.0
				if away.length() > 0.5:
					_face(away, delta)
					ragdoll.move_velocity = _forward() * crawl_speed * (0.4 + 0.6 * vitals.stamina)
					animator.speed = crawl_speed
		State.RAGDOLL:
			motor = 0.0
			balance = 0.0
			if vitals.is_conscious() and not _held:
				_timer -= delta
				if _timer <= 0.0 and ragdoll.hips_velocity().length() < 0.8:
					_enter(State.GET_UP if legs >= 0.6 else State.CRAWL)
		State.GET_UP:
			var blend := minf(_state_time / 1.4, 1.0)
			motor = blend
			balance = blend * blend
			if _state_time > 1.4:
				if ragdoll.tilt() < deg_to_rad(30.0) and ragdoll.hips_height() > 0.75:
					_enter(State.IDLE)
				elif _state_time > 4.0:
					knock_down(1.5)
		State.DEAD:
			motor = 0.0
			balance = 0.0

	if stunned:
		motor *= 0.7
		balance *= 0.75
	# Going limp is immediate; regaining control eases in.
	ragdoll.motor_strength = minf(motor, move_toward(ragdoll.motor_strength, motor, 6.0 * delta))
	ragdoll.balance_strength = minf(balance, move_toward(ragdoll.balance_strength, balance, 6.0 * delta))
	ragdoll.target_height = height + animator.height_offset
	animator.aim_weight = move_toward(animator.aim_weight, aim, 4.0 * delta)
	animator.update(delta, ragdoll.heading)
	if state == State.DEAD:
		set_physics_process(false)


## Called for every hit on any of the humanoid's hitboxes.
func on_hit(hitbox: HitboxComponent, info: DamageInfo) -> void:
	if state == State.DEAD:
		return
	alert(info.position - info.direction * 6.0)
	match info.type:
		DamageInfo.Type.BLAST:
			if info.overpressure > 15.0:
				knock_down(2.5 + info.overpressure / 40.0)
		DamageInfo.Type.BLUNT:
			if info.energy > 30.0:
				knock_down(2.0)
			elif info.energy > 12.0:
				stumble(0.6, info.direction)
		_:
			# Pellets and bursts arrive as separate hits; the body reacts to what they add up to.
			var frame := Engine.get_physics_frames()
			if frame - _impact_frame > int(REACTION_WINDOW * Engine.physics_ticks_per_second):
				_impact_energy = 0.0
				_impact_torso_energy = 0.0
			_impact_frame = frame
			_impact_energy += info.energy
			if hitbox.region == HitboxComponent.Region.TORSO:
				_impact_torso_energy += info.energy
			if _impact_energy > 900.0 or _impact_torso_energy > 600.0:
				knock_down(2.5)
			else:
				stumble(clampf(0.35 + _impact_energy / 1200.0, 0.35, 1.2), info.direction)


func stumble(seconds: float, direction: Vector3) -> void:
	if not (state in UPRIGHT):
		return
	var push := Vector3(direction.x, 0.0, direction.z).normalized() * 0.9
	_stagger = push + Vector3(randf() - 0.5, 0.0, randf() - 0.5) * 0.6
	_timer = maxf(seconds, _timer if state == State.STUMBLE else 0.0)
	_enter(State.STUMBLE)


## Full passive ragdoll for at least `seconds`; the NPC gets up afterwards if it still can.
func knock_down(seconds: float) -> void:
	if state == State.DEAD:
		return
	_timer = maxf(seconds, _timer if state == State.RAGDOLL else 0.0)
	_enter(State.RAGDOLL)


func alert(position: Vector3) -> void:
	has_threat = true
	threat_position = position
	if state == State.AIM:
		_timer = 8.0


## Gunfire nearby: armed NPCs turn and aim at it, unarmed ones cower.
func hear_noise(position: Vector3) -> void:
	if state == State.DEAD or humanoid.ragdoll.hips_position().distance_to(position) > alert_range:
		return
	alert(position)
	if not humanoid.is_armed() and (state == State.IDLE or state == State.WANDER):
		_enter(State.COWER)


## The physgun is holding one of this NPC's limbs.
func set_held(held: bool) -> void:
	_held = held
	if held:
		knock_down(1.0)
	else:
		_timer = 1.2


func _enter(next: State) -> void:
	if state == State.DEAD or next == state:
		return
	var previous := state
	state = next
	_state_time = 0.0
	_fallen_time = 0.0
	_air_time = 0.0
	match next:
		State.IDLE:
			_timer = randf_range(2.0, 5.0)
		State.AIM:
			_timer = 8.0
		State.RAGDOLL, State.DEAD:
			humanoid.ragdoll.motor_strength = 0.0
			humanoid.ragdoll.balance_strength = 0.0
	state_changed.emit(next, previous)


func _has_fallen(delta: float) -> bool:
	var ragdoll := humanoid.ragdoll
	_air_time = 0.0 if ragdoll.grounded else _air_time + delta
	var down := ragdoll.tilt() > deg_to_rad(60.0) or (ragdoll.grounded and ragdoll.hips_height() < ragdoll.target_height * 0.55)
	_fallen_time = _fallen_time + delta if down else 0.0
	return _fallen_time > 0.35 or _air_time > 0.4


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	var ragdoll := humanoid.ragdoll
	ragdoll.heading = rotate_toward(ragdoll.heading, atan2(-direction.x, -direction.z), TURN_RATE * delta)


func _forward() -> Vector3:
	var heading := humanoid.ragdoll.heading
	return Vector3(-sin(heading), 0.0, -cos(heading))


func _on_consciousness_changed(now: VitalsComponent.Consciousness, _previous: VitalsComponent.Consciousness) -> void:
	match now:
		VitalsComponent.Consciousness.DEAD:
			_enter(State.DEAD)
		VitalsComponent.Consciousness.UNCONSCIOUS:
			_timer = 0.5
			_enter(State.RAGDOLL)
