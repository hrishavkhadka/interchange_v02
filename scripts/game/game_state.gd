extends Node

signal state_changed(new_state: int)
signal timer_tick(remaining: float)
signal counters_changed(spawned: int, cleared: int, target: int)
signal failed()
signal passed()
signal elevation_changed(new_elevation: float)

enum State { BUILD, PLAYING, PAUSED, FAILED_PLAYING, PASSED_PLAYING }

var state: int = State.BUILD
var speed_multiplier: float = 1.0
var time_limit: float = 90.0
var time_remaining: float = 90.0
var target_count: int = 40
var default_target_count: int = 40
var spawned_count: int = 0
var cleared_count: int = 0

func start_play() -> void:
	if state == State.PAUSED:
		_set_state(State.PLAYING)
		return
	if state != State.BUILD:
		return
	_reset_counters()
	time_remaining = time_limit
	target_count = default_target_count
	_set_state(State.PLAYING)

func toggle_pause() -> void:
	if state == State.PLAYING or state == State.FAILED_PLAYING or state == State.PASSED_PLAYING:
		_set_state(State.PAUSED)
	elif state == State.PAUSED:
		_set_state(State.PLAYING)

func stop() -> void:
	_reset_counters()
	_set_state(State.BUILD)

func restart() -> void:
	_reset_counters()
	_set_state(State.BUILD)

func set_speed(m: float) -> void:
	speed_multiplier = m

func set_target(n: int) -> void:
	target_count = maxi(1, n)
	counters_changed.emit(spawned_count, cleared_count, target_count)

func is_playing() -> bool:
	return state == State.PLAYING or state == State.FAILED_PLAYING or state == State.PASSED_PLAYING

func is_build() -> bool:
	return state == State.BUILD

func register_spawn() -> void:
	spawned_count += 1
	counters_changed.emit(spawned_count, cleared_count, target_count)
	_check_passed()

func register_cleared() -> void:
	cleared_count += 1
	counters_changed.emit(spawned_count, cleared_count, target_count)
	_check_passed()

func _reset_counters() -> void:
	spawned_count = 0
	cleared_count = 0
	time_remaining = time_limit
	counters_changed.emit(spawned_count, cleared_count, target_count)
	timer_tick.emit(time_remaining)

func _set_state(s: int) -> void:
	state = s
	state_changed.emit(state)

func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	time_remaining -= delta * speed_multiplier
	if time_remaining <= 0.0:
		time_remaining = 0.0
		_set_state(State.FAILED_PLAYING)
		timer_tick.emit(time_remaining)
		failed.emit()
		return
	timer_tick.emit(time_remaining)

func _check_passed() -> void:
	if state != State.PLAYING:
		return
	if spawned_count >= target_count and cleared_count >= target_count:
		_set_state(State.PASSED_PLAYING)
		passed.emit()
