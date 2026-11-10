class_name PIDController
extends RefCounted
## Vector PID with derivative-on-measurement and a clamped integral.

var kp := 1.0
var ki := 0.0
var kd := 0.0
var integral_limit := 1.0

var _integral := Vector3.ZERO


func _init(p := 1.0, i := 0.0, d := 0.0, i_limit := 1.0) -> void:
	kp = p
	ki = i
	kd = d
	integral_limit = i_limit


func reset() -> void:
	_integral = Vector3.ZERO


## `rate` is the measured velocity of the controlled point rather than the error derivative,
## so a jumping target does not produce a derivative kick.
func step(error: Vector3, rate: Vector3, delta: float) -> Vector3:
	_integral = (_integral + error * delta).limit_length(integral_limit)
	return kp * error + ki * _integral - kd * rate
