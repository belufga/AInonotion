class_name VitalsComponent
extends Node
## Hemodynamic and physiological simulation for one humanoid.
##
## Blood volume sets preload; preload, heart function and heart rate set pressure; pressure,
## oxygen saturation and haemoglobin set cerebral perfusion; perfusion decides consciousness.
## Rates are time-compressed for gameplay, roughly 8x faster than real physiology.

enum Consciousness { AWAKE, STUNNED, UNCONSCIOUS, DEAD }

signal consciousness_changed(state: Consciousness, previous: Consciousness)
signal heartbeat(systolic_mmhg: float)
signal died(cause: String)
signal coughed_blood
signal wound_added(wound: Wound)

const NORMAL_MAP := 93.0
const MAX_WOUNDS := 24
## Stroke volume against remaining blood fraction (hemorrhagic shock classes I-IV).
const PRELOAD_CURVE := [Vector2(0.30, 0.0), Vector2(0.40, 0.12), Vector2(0.50, 0.35), Vector2(0.60, 0.62),
	Vector2(0.70, 0.85), Vector2(0.85, 1.0), Vector2(1.0, 1.0)]
## Arterial saturation against working lung fraction.
const SATURATION_CURVE := [Vector2(0.0, 0.0), Vector2(0.25, 0.72), Vector2(0.5, 0.93), Vector2(0.75, 1.0), Vector2(1.0, 1.0)]

@export var max_blood_volume := 5000.0     ## ml
@export var resting_heart_rate := 72.0     ## bpm
@export var tick_interval := 0.05          ## s; the slow physiology runs at 20 Hz
@export var hypoxia_tolerance := 10.0      ## s of failed cerebral perfusion before brain death
@export var arrest_volume_fraction := 0.45 ## remaining blood fraction at which the heart stops
@export var tension_time := 30.0           ## s for a punctured lung to collapse completely

var blood_volume := 5000.0
var heart_rate := 72.0
var systolic := 120.0
var diastolic := 80.0
var oxygen_saturation := 98.0
var consciousness := Consciousness.AWAKE
var pain := 0.0
var stamina := 1.0
var heart_function := 1.0
var brain_function := 1.0
var lung_integrity: Array[float] = [1.0, 1.0]  ## Left, right.
var lung_tension: Array[float] = [0.0, 0.0]
var cardiac_arrest := false
var cause_of_death := ""
var bleed_rate := 0.0         ## ml/s currently being lost.
var cerebral_perfusion := 1.0
var wounds: Array[Wound] = []

var blood_pressure: float:
	get:
		return systolic

var mean_arterial_pressure: float:
	get:
		return diastolic + (systolic - diastolic) / 3.0

var _accumulator := 0.0
var _beat_phase := 0.0
var _stun_time := 0.0
var _knockout_time := 0.0
var _hypoxia_debt := 0.0
var _cough_timer := 3.0
var _arrest_cause := ""
var _time_dead := 0.0


func _ready() -> void:
	blood_volume = max_blood_volume
	heart_rate = resting_heart_rate


func _physics_process(delta: float) -> void:
	_accumulator += delta
	while _accumulator >= tick_interval:
		_accumulator -= tick_interval
		_tick(tick_interval)
	# The pulse is advanced every frame so arterial spurts stay in sync with it.
	if heart_rate > 15.0 and systolic > 5.0:
		_beat_phase += heart_rate / 60.0 * delta
		if _beat_phase >= 1.0:
			_beat_phase = fmod(_beat_phase, 1.0)
			heartbeat.emit(systolic)


func is_alive() -> bool:
	return consciousness != Consciousness.DEAD


func is_conscious() -> bool:
	return consciousness == Consciousness.AWAKE or consciousness == Consciousness.STUNNED


func add_wound(wound: Wound) -> void:
	if wounds.size() >= MAX_WOUNDS:
		var weakest := 0
		for i in wounds.size():
			if wounds[i].rate < wounds[weakest].rate:
				weakest = i
		wounds.remove_at(weakest)
	wounds.append(wound)
	wound_added.emit(wound)


func add_pain(amount: float) -> void:
	pain = clampf(pain + amount, 0.0, 1.0)


func stun(seconds: float) -> void:
	_stun_time = maxf(_stun_time, seconds)


func knock_out(seconds: float) -> void:
	_knockout_time = maxf(_knockout_time, seconds)
	if is_conscious():
		_set_consciousness(Consciousness.UNCONSCIOUS)


func damage_heart(severity: float) -> void:
	heart_function = maxf(heart_function - severity, 0.0)


func damage_lung(index: int, severity: float) -> void:
	lung_integrity[index] = maxf(lung_integrity[index] - severity, 0.0)
	_cough_timer = minf(_cough_timer, 0.8)


## Brain destruction is the one instantaneous death: motor control ends on the same frame.
func damage_brain(severity: float) -> void:
	brain_function = maxf(brain_function - severity, 0.0)
	if brain_function <= 0.0:
		_die("brain destruction")


func kill(cause: String) -> void:
	brain_function = 0.0
	_die(cause)


func summary() -> String:
	var state: String = Consciousness.keys()[consciousness]
	var text := "%s\nBlood %d ml (-%.0f ml/s)\nBP %d/%d mmHg   HR %d bpm\nSpO2 %d%%   Pain %d%%" % [
		state.capitalize(), roundi(blood_volume), bleed_rate, roundi(systolic), roundi(diastolic),
		roundi(heart_rate), roundi(oxygen_saturation), roundi(pain * 100.0)]
	if cause_of_death != "":
		text += "\nCause: " + cause_of_death
	elif cardiac_arrest:
		text += "\nCardiac arrest: " + _arrest_cause
	return text


func _tick(dt: float) -> void:
	var dead := consciousness == Consciousness.DEAD
	_bleed(dt)
	var volume := blood_volume / max_blood_volume

	# Respiration. A punctured lung keeps leaking air into the pleural space until it has
	# collapsed and starts to obstruct venous return (tension pneumothorax).
	var breathing := not dead and brain_function > 0.2
	var tension := 0.0
	var ventilation := 0.0
	for i in 2:
		if lung_integrity[i] < 1.0 and breathing:
			lung_tension[i] = minf(lung_tension[i] + dt / tension_time, 1.0)
		tension = maxf(tension, lung_tension[i])
		ventilation += 0.5 * lung_integrity[i] * (1.0 - 0.9 * lung_tension[i])
	if not breathing:
		ventilation = 0.0

	if not cardiac_arrest:
		if heart_function < 0.05:
			_arrest("cardiac destruction")
		elif volume <= arrest_volume_fraction:
			_arrest("hemorrhagic shock")
		elif oxygen_saturation < 30.0:
			_arrest("asphyxia")

	# Heart rate: baroreflex tachycardia plus pain and hypoxic drive.
	var shock := clampf((1.0 - volume) / 0.4, 0.0, 1.0)
	var target_rate := 0.0
	if not cardiac_arrest:
		var hypoxic_drive := clampf((92.0 - oxygen_saturation) / 20.0, 0.0, 1.0)
		target_rate = minf(resting_heart_rate + 85.0 * shock + 40.0 * pain + 30.0 * hypoxic_drive, 190.0)
	heart_rate = move_toward(heart_rate, target_rate, (60.0 if cardiac_arrest else 25.0) * dt)

	# Pressure follows cardiac output; vasoconstriction hides early blood loss.
	var stroke := _sample(PRELOAD_CURVE, volume)
	if tension > 0.6:
		stroke *= 1.0 - 0.6 * (tension - 0.6) / 0.4
	var rate_factor := sqrt(clampf(heart_rate / resting_heart_rate, 0.0, 1.25))
	var output := stroke * heart_function * rate_factor * (1.0 + 0.25 * shock)
	var target_systolic := 0.0 if cardiac_arrest else 120.0 * minf(output, 1.0)
	systolic += (target_systolic - systolic) * (1.0 - exp(-dt / 1.2))
	diastolic = systolic * 0.66

	var target_saturation := 0.0 if cardiac_arrest else 98.0 * _sample(SATURATION_CURVE, ventilation)
	var tau := 9.0 if target_saturation < oxygen_saturation else 5.0
	oxygen_saturation += (target_saturation - oxygen_saturation) * (1.0 - exp(-dt / tau))

	# Oxygen delivery to the brain: autoregulated above a MAP of 70 mmHg, gone below 35.
	var perfusion := clampf((mean_arterial_pressure - 35.0) / 35.0, 0.0, 1.0)
	var oxygen := clampf(oxygen_saturation / 95.0, 0.0, 1.0)
	var hemoglobin := clampf(volume / 0.6, 0.0, 1.0)
	cerebral_perfusion = perfusion * oxygen * oxygen * hemoglobin * brain_function
	if cerebral_perfusion < 0.25:
		_hypoxia_debt += dt * (1.0 - cerebral_perfusion / 0.25)
	else:
		_hypoxia_debt = maxf(_hypoxia_debt - dt * 0.5, 0.0)

	pain = maxf(pain - 0.035 * dt, 0.0)
	_stun_time = maxf(_stun_time - dt, 0.0)
	_knockout_time = maxf(_knockout_time - dt, 0.0)
	stamina = move_toward(stamina, ventilation * clampf(oxygen_saturation / 98.0, 0.0, 1.0), 0.15 * dt)

	if dead:
		_time_dead += dt
		if cardiac_arrest and _time_dead > 40.0:
			set_physics_process(false)
		return
	if _hypoxia_debt >= hypoxia_tolerance:
		_die(_arrest_cause if cardiac_arrest else "cerebral hypoxia")
		return
	_update_cough(dt, breathing)

	var next := Consciousness.AWAKE
	var blackout_threshold := 0.5 if consciousness == Consciousness.UNCONSCIOUS else 0.4
	if cerebral_perfusion < blackout_threshold or _knockout_time > 0.0:
		next = Consciousness.UNCONSCIOUS
	elif cerebral_perfusion < 0.65 or volume < 0.62 or pain > 0.8 or _stun_time > 0.0:
		next = Consciousness.STUNNED
	_set_consciousness(next)


func _bleed(dt: float) -> void:
	var pressure := clampf(mean_arterial_pressure / NORMAL_MAP, 0.0, 1.3)
	var lost := 0.0
	var i := wounds.size() - 1
	while i >= 0:
		var w := wounds[i]
		if not w.is_valid() or w.rate < 0.05:
			wounds.remove_at(i)
		else:
			# Arterial flow is driven by pressure alone; venous and capillary ooze keeps a gravity term.
			w.flow = w.rate * (pressure if w.arterial else 0.3 + 0.7 * pressure)
			if cardiac_arrest:
				w.rate *= exp(-dt / 12.0)
			elif w.clot_halflife > 0.0:
				w.rate *= pow(0.5, dt / w.clot_halflife)
			var amount := minf(w.flow * dt, blood_volume - lost)
			w.lost += amount
			w.pending += amount
			lost += amount
		i -= 1
	blood_volume = maxf(blood_volume - lost, 0.0)
	bleed_rate = lost / dt


func _update_cough(dt: float, breathing: bool) -> void:
	if not breathing or (lung_integrity[0] >= 1.0 and lung_integrity[1] >= 1.0):
		return
	_cough_timer -= dt
	if _cough_timer <= 0.0:
		_cough_timer = randf_range(2.5, 6.0)
		blood_volume = maxf(blood_volume - 8.0, 0.0)
		pain = minf(pain + 0.05, 1.0)
		stamina = maxf(stamina - 0.15, 0.0)
		coughed_blood.emit()


func _arrest(cause: String) -> void:
	cardiac_arrest = true
	_arrest_cause = cause


func _die(cause: String) -> void:
	if consciousness == Consciousness.DEAD:
		return
	cause_of_death = cause
	_set_consciousness(Consciousness.DEAD)
	died.emit(cause)


func _set_consciousness(next: Consciousness) -> void:
	if next == consciousness:
		return
	var previous := consciousness
	consciousness = next
	consciousness_changed.emit(next, previous)


static func _sample(curve: Array, x: float) -> float:
	if x <= curve[0].x:
		return curve[0].y
	for i in range(1, curve.size()):
		if x <= curve[i].x:
			var a: Vector2 = curve[i - 1]
			var b: Vector2 = curve[i]
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return curve[-1].y
