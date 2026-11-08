class_name SnapshotBuffer
extends RefCounted
## Client-side interpolation buffer for ONE remote player. Samples are stamped with the local
## receive time; sample(t) is asked for (now - INTERP_DELAY) so there are normally two samples
## to blend between, which hides jitter and the 20 Hz update rate.

const MAX_SAMPLES := 24

var _t: Array[float] = []
var _pos: Array[Vector3] = []
var _yaw: Array[float] = []
var _speed: Array[float] = []
var _flags: Array[int] = []


func push(time: float, pos: Vector3, yaw: float, speed: float, flags: int) -> void:
	if not _t.is_empty() and time <= _t[_t.size() - 1]:
		time = _t[_t.size() - 1] + 0.001
	_t.append(time)
	_pos.append(pos)
	_yaw.append(yaw)
	_speed.append(speed)
	_flags.append(flags)
	if _t.size() > MAX_SAMPLES:
		_t.pop_front()
		_pos.pop_front()
		_yaw.pop_front()
		_speed.pop_front()
		_flags.pop_front()


func is_empty() -> bool:
	return _t.is_empty()


## Returns {pos, yaw, speed, flags} at render time `t`, or {} if there is no data yet.
func sample(t: float) -> Dictionary:
	var n := _t.size()
	if n == 0:
		return {}
	if t <= _t[0]:
		return _make(0, 0, 0.0)
	if t >= _t[n - 1]:
		# Nothing newer than t: hold the last known state (no extrapolation = no overshoot).
		return _make(n - 1, n - 1, 0.0)
	for i in range(n - 1):
		if t >= _t[i] and t <= _t[i + 1]:
			var span := _t[i + 1] - _t[i]
			return _make(i, i + 1, (t - _t[i]) / span if span > 0.0001 else 1.0)
	return _make(n - 1, n - 1, 0.0)


func _make(a: int, b: int, w: float) -> Dictionary:
	return {
		"pos": _pos[a].lerp(_pos[b], w),
		"yaw": lerp_angle(_yaw[a], _yaw[b], w),
		"speed": lerpf(_speed[a], _speed[b], w),
		"flags": _flags[b] if w >= 0.5 else _flags[a],
	}
