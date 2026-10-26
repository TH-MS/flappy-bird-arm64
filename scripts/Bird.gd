class_name Bird
extends Node2D
## The bird: physics, hit box and sprite animation.
##
## Coordinates are the ORIGINAL 288x512 playfield. `x`/`y` are the top-left of the
## 20x20 hit box (the original's `b`/`c` fields); the 48x48 sprite is centred on it.
## Every positional update is multiplied by the frame delta (seconds), so motion is
## identical at 30/60/90/120/144 Hz. Call `tick(dt)` once per frame from Main.

signal flapped            ## emitted on every accepted flap (hook the wing sound here)
signal landed             ## emitted once when the bird reaches the ground

enum State { IDLE, FLYING, DEAD }

## true  = constants fitted to the original's int-truncated per-tick motion (default, plays like the APK)
## false = plain unit conversion of the Java numbers (300 px/s, 1080 px/s^2)
@export var use_fitted_physics: bool = true

const FLAP_SEQUENCE: Array[int] = [0, 1, 2, 1, 0, 1, 2, 1, 0, 1, 2, 1]

var state: State = State.IDLE
var x: float = Config.BIRD_X
var y: float = Config.BIRD_START_Y     # top edge of hit box
var velocity: float = 0.0               # px/s, +down
var angle_deg: float = 0.0              # +clockwise (nose down)
var angular_velocity: float = 0.0       # deg/s
var on_ground: bool = false
var skin: int = 0                       # 0..2 = bird0_*, bird1_*, bird2_*

var _bob_phase: float = 0.0
var _bob: float = 0.0
var _anim_clock: float = 0.0
var _flap_playing: bool = false
var _frames: Array[Texture2D] = []
var _sprite: Sprite2D


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = true
	add_child(_sprite)
	set_skin(skin)
	_apply_transform()


func set_skin(index: int) -> void:
	skin = clampi(index, 0, 2)
	_frames.clear()
	for f in 3:
		_frames.append(Atlas.tex("bird%d_%d" % [skin, f]))
	if _sprite:
		_sprite.texture = _frames[1]


## Back to the hovering "ready" pose. `at_x`/`at_y` let the menu park it elsewhere.
func reset(new_skin: int, at_x: float = Config.BIRD_X, at_y: float = Config.BIRD_START_Y) -> void:
	state = State.IDLE
	x = at_x
	y = at_y
	velocity = 0.0
	angle_deg = 0.0
	angular_velocity = 0.0
	on_ground = false
	_bob_phase = 0.0
	_bob = Config.BOB_AMPLITUDE
	_anim_clock = 0.0
	_flap_playing = false
	set_skin(new_skin)
	_apply_transform()


func hitbox() -> Rect2:
	return Rect2(x, y, Config.BIRD_HIT_W, Config.BIRD_HIT_H)


## Returns true if the flap was accepted. Like the original, a flap is ignored while
## the bird is above the top of the screen (y < 0) and once it is dead.
func flap() -> bool:
	if state == State.DEAD:
		return false
	state = State.FLYING                       # first tap leaves the hover state
	if y < 0.0:
		return false
	velocity = -(Config.JUMP_SPEED_FITTED if use_fitted_physics else Config.JUMP_SPEED_RAW)
	angular_velocity = Config.ANGLE_VEL_FLAP
	_anim_clock = 0.0
	_flap_playing = true
	flapped.emit()
	return true


## Collision happened: no more input, gravity keeps pulling.
func die() -> void:
	state = State.DEAD


func tick(dt: float) -> void:
	_anim_clock += dt
	match state:
		State.IDLE:
			_bob_phase = fposmod(_bob_phase + Config.BOB_DEG_PER_SEC * dt, 360.0)
			_bob = cos(deg_to_rad(_bob_phase)) * Config.BOB_AMPLITUDE
		_:
			_bob = 0.0
			_integrate(dt)
	_update_frame()
	_apply_transform()


func _integrate(dt: float) -> void:
	if not on_ground:
		var g := Config.GRAVITY_FITTED if use_fitted_physics else Config.GRAVITY_RAW
		var v_new := minf(velocity + g * dt, Config.TERMINAL_SPEED)
		y += 0.5 * (velocity + v_new) * dt     # exact for constant acceleration => dt-independent arc
		velocity = v_new
		if y >= Config.BIRD_GROUND_Y:
			y = Config.BIRD_GROUND_Y
			velocity = 0.0
			on_ground = true
			landed.emit()
	# rotation keeps evolving on the ground too (original behaviour) until it hits 90 deg
	angular_velocity += Config.ANGLE_ACCEL * dt
	angle_deg = clampf(angle_deg + angular_velocity * dt, Config.ANGLE_MIN, Config.ANGLE_MAX)


func _update_frame() -> void:
	var idx := 1
	if state == State.IDLE:
		idx = FLAP_SEQUENCE[int(_anim_clock / Config.IDLE_FRAME_TIME) % FLAP_SEQUENCE.size()]
	elif _flap_playing:
		var step := int(_anim_clock / Config.FLAP_FRAME_TIME)
		if step >= FLAP_SEQUENCE.size():
			_flap_playing = false
		else:
			idx = FLAP_SEQUENCE[step]
	if _sprite and not _frames.is_empty():
		_sprite.texture = _frames[idx]


func _apply_transform() -> void:
	# hit box centre == sprite centre (48 = 14 + 20 + 14)
	position = Vector2(x + Config.BIRD_HIT_W * 0.5, y + Config.BIRD_HIT_H * 0.5 + _bob)
	rotation = deg_to_rad(angle_deg)
