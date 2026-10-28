extends Node2D
## Game flow, rendering layout, input, audio hooks and high-score persistence.
##
## The playfield uses the ORIGINAL 288x512 coordinates inside `world`. `world` is
## pinned to the BOTTOM-centre of the screen, so on a 19.5:9 phone the extra height
## becomes extra sky above the old top edge (see _layout). Gameplay is therefore
## identical on every aspect ratio; only the visible area changes.
##
## All motion is driven by `step(dt)` with dt = frame delta in seconds (clamped), so
## 60/90/120/144 Hz behave the same. Tests can call `step()` directly.

signal score_changed(new_score: int)
signal game_over(final_score: int, best_score: int)
signal leaderboard_requested     ## "Score" button -> hook Google Play Games / your backend
signal rate_requested            ## "Rate" button  -> hook your store listing

const SAVE_PATH := "user://flappy_save.cfg"
const RATE_URL := ""             ## set to your store URL to show the Rate button
const AUDIO_DIR := "res://assets/audio/"
const SFX_FILES := {
	"point": "sfx_point.ogg",
	"die": "sfx_die.ogg",
	"hit": "sfx_hit.ogg",
	"swoosh": "sfx_swooshing.ogg",
	"wing": "sfx_wing.ogg",
}

enum State { MENU, READY, PLAYING, DYING, GAME_OVER }

# ------------------------------------------------------------------ tiny helpers
class Ease:
	static func apply(kind: int, u: float) -> float:
		match kind:
			5:   # cubic out  (original easing id 5)
				var d := u - 1.0
				return d * d * d + 1.0
			11:  # quintic out (original easing id 11)
				var d2 := u - 1.0
				return d2 * d2 * d2 * d2 * d2 + 1.0
		return u

class Tween1:
	var from_v := 0.0
	var to_v := 0.0
	var duration := 1.0
	var kind := 0
	var t := 0.0
	var done := true
	var value := 0.0
	func start(a: float, b: float, d: float, k: int = 0) -> void:
		from_v = a; to_v = b; duration = maxf(d, 0.0001); kind = k
		t = 0.0; done = false; value = a
	## returns true on the step in which the tween finishes
	func step(dt: float) -> bool:
		if done:
			return false
		t += dt
		if t >= duration:
			value = to_v
			done = true
			return true
		value = from_v + (to_v - from_v) * Ease.apply(kind, t / duration)
		return false

## Sprite-font number renderer (HUD font or score-panel digits).
class DigitRow extends Node2D:
	var hud_font := true
	var _pool: Array[Sprite2D] = []

	func _digit_name(d: int) -> String:
		return ("font_%03d" % (48 + d)) if hud_font else ("number_score_%02d" % d)

	func _slot(i: int) -> Sprite2D:
		while _pool.size() <= i:
			var s := Sprite2D.new()
			s.centered = false
			add_child(s)
			_pool.append(s)
		return _pool[i]

	func _digits(value: int) -> Array[int]:
		var out: Array[int] = []
		var v := maxi(value, 0)
		if v == 0:
			out.append(0)
		while v > 0:
			out.push_front(v % 10)
			v /= 10
		return out

	## HUD: centred on (cx, cy); glyphs overlap by 4 px exactly like the original.
	func show_centered(value: int, cx: float, cy: float) -> void:
		var ds := _digits(value)
		var total := 2
		for d in ds:
			total += int(Atlas.size_of(_digit_name(d)).x) - 4
		var px := cx - floorf(total / 2.0)
		for i in _pool.size():
			_pool[i].visible = false
		for i in ds.size():
			var n := _digit_name(ds[i])
			var s := _slot(i)
			s.texture = Atlas.tex(n)
			s.position = Vector2(px, cy - 22.0)
			s.visible = true
			px += Atlas.size_of(n).x - 4.0

	## Score panel: right-aligned at `right_x`, 16 px per digit.
	func show_right(value: int, right_x: float, y: float) -> void:
		var ds := _digits(value)
		for i in _pool.size():
			_pool[i].visible = false
		var px := right_x - 16.0
		for i in range(ds.size() - 1, -1, -1):
			var s := _slot(i)
			s.texture = Atlas.tex(_digit_name(ds[i]))
			s.position = Vector2(px, y)
			s.visible = true
			px -= 16.0

class Btn:
	var sprite: Sprite2D
	var pos := Vector2.ZERO
	var size := Vector2.ZERO
	var enabled := false
	var action: Callable
	func contains(p: Vector2) -> bool:   # +8 px thumb padding
		return p.x > pos.x - 8.0 and p.x < pos.x + size.x + 8.0 and p.y > pos.y - 8.0 and p.y < pos.y + size.y + 8.0
	func set_enabled(on: bool) -> void:
		enabled = on
		sprite.visible = on
		sprite.position = pos
	func set_down(down: bool) -> void:
		sprite.position = pos + Vector2(0.0, 2.0 if down else 0.0)   # original: pressed = +2 px

class Spark:
	var sprite: Sprite2D
	var t := 0.0
	var active := false

# ------------------------------------------------------------------ state
var state: State = State.MENU
var score: int = 0
var best: int = 0
var rng := RandomNumberGenerator.new()

var world: Node2D
var bird: Bird
var pipes: PipeManager

var _bg_tiles: Array[Sprite2D] = []
var _bg_top: Sprite2D
var _bg_name := "bg_day"
var _land_tiles: Array[Sprite2D] = []
var _ground_x := 0.0
var _view := Vector2(Config.GAME_W, Config.GAME_H)

var _hud: DigitRow
var _title: Sprite2D
var _copyright: Label
var _ready_text: Sprite2D
var _tutorial: Sprite2D
var _go_text: Sprite2D
var _panel: Node2D
var _panel_score: DigitRow
var _panel_best: DigitRow
var _medal: Sprite2D
var _new_badge: Sprite2D
var _buttons: Array[Btn] = []
var _btn_play: Btn
var _btn_score: Btn
var _btn_rate: Btn
var _pressed: Btn = null
var _sparks: Array[Spark] = []
var _spark_timer := 0.0
var _medal_index := -1

var _flash_rect: ColorRect
var _fade_rect: ColorRect
var _flash := Tween1.new()
var _fade := Tween1.new()
var _ready_a := Tween1.new()
var _go_a := Tween1.new()
var _panel_y := Tween1.new()
var _count := Tween1.new()
var _fading_out := false
var _go_phase := -1
var _go_hop := 0.0
var _go_hop_v := 0.0
var _panel_best_shown := 0
var _was_new_best := false

var _splash_layer: CanvasLayer
var _splash_left := 0.0          # seconds of splash still to show (0 = none)
var _splash_fade := 0.0

const LB_H := 200.0              # leaderboard panel height (original panel is 126 px tall)
const LB_ROWS := 5

var scores: Array[int] = []      # personal top scores, best first
var _lb: Node2D
var _lb_ranks: Array[Sprite2D] = []
var _lb_values: Array[DigitRow] = []

var lift_frac := 0.0             # options: 0 = original (lowest) position, 1 = highest that fits
var fps60 := false               # options: cap at 60 fps
var _lift := 0.0                 # lift in view units
var _opts: Options
var _fill: Array[Sprite2D] = []  # ground extension below the playfield when it is lifted

var _events: Array = []          # [seconds_left, Callable]
var _players: Dictionary = {}


# ================================================================== lifecycle
func _ready() -> void:
	rng.randomize()
	_load_best()
	_build_scene()
	_build_audio()
	_apply_fps()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_enter_menu()
	_build_splash()


func _process(delta: float) -> void:
	step(minf(delta, Config.MAX_DT))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			get_tree().paused = true
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			get_tree().paused = false


## Advance the whole game by `dt` seconds (frame-rate independent).
func step(dt: float) -> void:
	_step_splash(dt)
	_opts.set_button_visible((state == State.MENU or state == State.READY) and _splash_left <= 0.0 and _splash_layer == null and not _fading_out)
	_run_events(dt)
	_step_tweens(dt)

	# ground scrolls in menu / ready / playing, stops when the bird dies (original: ao = 0)
	if state == State.MENU or state == State.READY or state == State.PLAYING:
		_ground_x = fposmod(_ground_x + Config.SCROLL_SPEED * dt, float(Config.LAND_PERIOD))
		_place_ground()

	match state:
		State.PLAYING:
			pipes.tick(dt)
			bird.tick(dt)
			_check_collisions()
		_:
			bird.tick(dt)

	if state == State.GAME_OVER:
		_step_game_over(dt)


# ================================================================== input
func _input(event: InputEvent) -> void:
	# Touch only: mouse is turned into touch by project setting emulate_touch_from_mouse,
	# and emulate_mouse_from_touch is off, so a tap can never fire twice.
	if event is InputEventScreenTouch:
		var p := world.to_local(event.position)
		if event.pressed:
			_on_press(p)
		else:
			_on_release(p)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_UP, KEY_ENTER, KEY_KP_ENTER]:
			_on_action_key()


func _on_press(p: Vector2) -> void:
	if _fading_out or _splash_left > 0.0:
		return
	match state:
		State.MENU, State.GAME_OVER:
			if _lb.visible:
				var on_button := false
				for b in _buttons:
					if b.enabled and b.contains(p):
						on_button = true
				if not on_button:
					_lb.visible = false        # tap anywhere else closes the list
					return
			for b in _buttons:
				if b.enabled and b.contains(p):
					b.set_down(true)
					_pressed = b
					break
		State.READY:
			_start_run()
		State.PLAYING:
			bird.flap()


func _on_release(p: Vector2) -> void:
	if _pressed == null:
		return
	var b := _pressed
	_pressed = null
	b.set_down(false)
	if b.enabled and b.contains(p) and not _fading_out:
		b.action.call()


func _on_action_key() -> void:
	match state:
		State.READY: _start_run()
		State.PLAYING: bird.flap()
		State.MENU, State.GAME_OVER:
			if _btn_play.enabled and not _fading_out:
				_btn_play.action.call()


# ================================================================== flow
func _enter_menu() -> void:
	state = State.MENU
	score = 0
	_pick_background()
	bird.reset(rng.randi() % 3, (Config.GAME_W - Config.BIRD_HIT_W) * 0.5, 218.0)
	pipes.reset()
	_hud.visible = false
	_title.visible = true
	_copyright.visible = true
	_ready_text.visible = false
	_tutorial.visible = false
	_go_text.visible = false
	_panel.visible = false
	_set_buttons(true, true, RATE_URL != "")


func _start_run() -> void:
	state = State.PLAYING
	_ready_a.start(1.0, 0.0, Config.FADE_TIME, 0)     # "get ready" fades out (0.5 s)
	pipes.scrolling = true
	bird.flap()


func _begin_restart() -> void:
	_lb.visible = false
	_sfx("swoosh")
	_fading_out = true
	_set_buttons(false, false, false)
	_fade.start(0.0, 1.0, Config.FADE_TIME, 5)        # to black, cubic-out


func _do_restart() -> void:
	score = 0
	_pick_background()
	bird.reset(rng.randi() % 3)
	pipes.reset()
	_title.visible = false
	_copyright.visible = false
	_go_text.visible = false
	_panel.visible = false
	_hud.visible = true
	_hud.show_centered(0, Config.GAME_W * 0.5, 100.0)
	_ready_text.visible = true
	_tutorial.visible = true
	_ready_a.start(0.0, 1.0, Config.FADE_TIME, 0)
	_go_phase = -1
	_medal.visible = false
	_new_badge.visible = false
	for s in _sparks:
		s.active = false
		s.sprite.visible = false
	state = State.READY
	score_changed.emit(score)
	_fade.start(1.0, 0.0, Config.FADE_TIME, 0)        # back from black


func _on_scored() -> void:
	score += 1
	_hud.show_centered(score, Config.GAME_W * 0.5, 100.0)
	_sfx("point")
	score_changed.emit(score)


func _check_collisions() -> void:
	if bird.y >= Config.BIRD_GROUND_Y:
		_crash(false)
	elif pipes.collides(bird.hitbox()):
		_crash(true)


func _crash(hit_pipe: bool) -> void:
	state = State.DYING
	bird.die()
	pipes.scrolling = false
	_flash.start(1.0, 0.0, Config.FLASH_TIME, 11)     # white flash, quintic-out
	_sfx("hit")
	if hit_pipe:
		_after(Config.DIE_SOUND_DELAY, func(): _sfx("die"))
	_after(Config.GAME_OVER_DELAY, _show_game_over)


func _show_game_over() -> void:
	state = State.GAME_OVER
	_hud.visible = false
	_panel_best_shown = best
	_was_new_best = score > best
	if _was_new_best:
		best = score
	_record_score()                                   # persisted immediately, not at end of animation
	game_over.emit(score, best)
	_sfx("swoosh")
	_go_text.visible = true
	_go_a.start(0.0, 1.0, 1.0, 11)
	_go_hop = -1.0
	_go_hop_v = -2.0 * Config.TICK_RATE               # -2 px/tick
	_go_phase = 0


func _step_game_over(dt: float) -> void:
	# "GAME OVER" hop: c += v ; v += 0.25/tick   (ends when it settles back at 0)
	if _go_hop < 0.0:
		_go_hop += _go_hop_v * dt
		_go_hop_v += 0.25 * Config.TICK_RATE * Config.TICK_RATE * dt
		if _go_hop >= 0.0:
			_go_hop = 0.0
	_go_text.position = Vector2((Config.GAME_W - Atlas.size_of("text_game_over").x) * 0.5, 130.0 + _go_hop)
	_go_text.modulate.a = _go_a.value

	match _go_phase:
		0:
			if _go_a.done:
				_go_phase = 1
				_sfx("swoosh")
				_panel.visible = true
				_panel_score.show_right(0, 210.0, 36.0)
				_panel_best.show_right(_panel_best_shown, 210.0, 78.0)
				_panel_y.start(504.0, (Config.GAME_H - Atlas.size_of("score_panel").y) * 0.5, 0.5, 11)
		1:
			_panel.position = Vector2((Config.GAME_W - Atlas.size_of("score_panel").x) * 0.5, _panel_y.value)
			if _panel_y.done:
				if score > 0:
					_go_phase = 2
					_count.start(0.0, float(score), 0.5, 0)
				else:
					_finish_panel()
		2:
			_panel_score.show_right(int(_count.value), 210.0, 36.0)
			if _count.done:
				_finish_panel()
		3:
			_step_sparks(dt)


func _finish_panel() -> void:
	_go_phase = 3
	_panel_score.show_right(score, 210.0, 36.0)
	if _was_new_best:
		_panel_best.show_right(best, 210.0, 78.0)
		_new_badge.visible = true
	_medal_index = -1
	for i in Config.MEDAL_THRESHOLDS.size():
		if score >= Config.MEDAL_THRESHOLDS[i]:
			_medal_index = i
			break
	_medal.visible = _medal_index >= 0
	if _medal.visible:
		_medal.texture = Atlas.tex("medals_%d" % _medal_index)
		_spark_timer = 0.5
	_set_buttons(true, true, false)                   # Play + Score (original: y = 340)


func _step_sparks(dt: float) -> void:
	if _medal_index >= 0:
		_spark_timer -= dt
		if _spark_timer <= 0.0:
			_spark_timer = 0.5
			for s in _sparks:
				if not s.active:
					s.active = true
					s.t = 0.0
					s.sprite.visible = true
					s.sprite.position = Vector2(32.0 - 3.0 + rng.randi_range(0, 50), 44.0 - 3.0 + rng.randi_range(0, 50)) - Vector2(4, 4)
					break
	var seq := [0, 1, 2, 1, 0]
	for s in _sparks:
		if s.active:
			s.t += dt
			var i := int(s.t / Config.IDLE_FRAME_TIME)
			if i >= seq.size():
				s.active = false
				s.sprite.visible = false
			else:
				s.sprite.texture = Atlas.tex("blink_%02d" % seq[i])


func _step_tweens(dt: float) -> void:
	_flash.step(dt)
	_flash_rect.color.a = _flash.value
	if _fade.step(dt) and _fading_out:
		_fading_out = false
		_do_restart()
	_fade_rect.color.a = _fade.value
	_ready_a.step(dt)
	_ready_text.modulate.a = _ready_a.value
	_tutorial.modulate.a = _ready_a.value
	_go_a.step(dt)
	_panel_y.step(dt)
	_count.step(dt)


# ================================================================== scene building
func _build_scene() -> void:
	world = Node2D.new()
	add_child(world)

	_bg_top = Sprite2D.new()
	_bg_top.centered = false
	world.add_child(_bg_top)

	pipes = PipeManager.new()
	pipes.scored.connect(_on_scored)
	# the world's draw order is: background < pipes < bird < ground < UI
	for i in 4:
		_bg_tiles.append(_spr("bg_day", world))
	world.add_child(pipes)

	bird = Bird.new()
	bird.flapped.connect(func(): _sfx("wing"))
	world.add_child(bird)

	for i in 3:
		_land_tiles.append(_spr("land", world))
	for i in 3:                                      # 1-px sand row stretched down when the playfield is lifted
		var f := Sprite2D.new()
		f.centered = false
		f.texture = Atlas.strip("land", 111)
		f.visible = false
		world.add_child(f)
		_fill.append(f)

	var ui := Node2D.new()
	world.add_child(ui)
	_title = _spr("title", ui, Vector2((Config.GAME_W - 178) * 0.5, 150))
	_copyright = Label.new()                      # real text (Silkscreen) instead of the low-res sprite
	_copyright.text = "\u00a9 .GEARS 2013"
	_copyright.position = Vector2(0, 417)
	_copyright.size = Vector2(Config.GAME_W, 14)
	_copyright.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_copyright.add_theme_font_override("font", Options.make_font())
	_copyright.add_theme_font_size_override("font_size", 8)
	_copyright.add_theme_color_override("font_color", Color(250.0 / 255.0, 250.0 / 255.0, 250.0 / 255.0))
	_copyright.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	_copyright.add_theme_constant_override("shadow_offset_x", 0)
	_copyright.add_theme_constant_override("shadow_offset_y", 1)
	_copyright.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_copyright)
	_ready_text = _spr("text_ready", ui, Vector2((Config.GAME_W - 196) * 0.5, 146))
	_tutorial = _spr("tutorial", ui, Vector2((Config.GAME_W - 114) * 0.5, 220))
	_go_text = _spr("text_game_over", ui, Vector2(42, 130))
	_hud = DigitRow.new()
	ui.add_child(_hud)

	_panel = Node2D.new()
	ui.add_child(_panel)
	_spr("score_panel", _panel)
	_panel_score = DigitRow.new()
	_panel_score.hud_font = false
	_panel.add_child(_panel_score)
	_panel_best = DigitRow.new()
	_panel_best.hud_font = false
	_panel.add_child(_panel_best)
	_medal = _spr("medals_3", _panel, Vector2(32, 44))
	_new_badge = _spr("new", _panel, Vector2(142, 60))
	for i in 4:
		var sp := Spark.new()
		sp.sprite = _spr("blink_00", _panel)
		sp.sprite.visible = false
		_sparks.append(sp)

	_build_leaderboard(ui)
	_btn_play = _button("button_play", Vector2(20, 340), _begin_restart, ui)
	_btn_score = _button("button_score", Vector2(152, 340), _on_score_button, ui)
	_btn_rate = _button("button_rate", Vector2(107, 270), _on_rate_button, ui)

	# full-screen overlays (screen space, above everything)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_flash_rect = _overlay(Color(1, 1, 1, 0), layer)
	_fade_rect = _overlay(Color(0, 0, 0, 0), layer)

	_opts = Options.new()
	add_child(_opts)
	_opts.set_values(lift_frac, fps60)
	_opts.lift_changed.connect(_on_lift_changed)
	_opts.fps_changed.connect(_on_fps_changed)
	_opts.closed.connect(_save_best)


func _spr(sprite_name: String, parent: Node, pos: Vector2 = Vector2.ZERO) -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.texture = Atlas.tex(sprite_name)
	s.position = pos
	parent.add_child(s)
	return s


func _button(sprite_name: String, pos: Vector2, action: Callable, parent: Node) -> Btn:
	var b := Btn.new()
	b.sprite = _spr(sprite_name, parent, pos)
	b.pos = pos
	b.size = Atlas.size_of(sprite_name)
	b.action = action
	b.set_enabled(false)
	_buttons.append(b)
	return b


func _overlay(c: Color, layer: CanvasLayer) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(r)
	return r


func _on_score_button() -> void:
	_sfx("swoosh")
	_lb.visible = not _lb.visible
	if _lb.visible:
		_refresh_leaderboard()
	leaderboard_requested.emit()


func _on_rate_button() -> void:
	rate_requested.emit()
	if RATE_URL != "":
		OS.shell_open(RATE_URL)


func _set_buttons(play: bool, score_btn: bool, rate: bool) -> void:
	_btn_play.set_enabled(play)
	_btn_score.set_enabled(score_btn)
	_btn_rate.set_enabled(rate)
	_pressed = null


func _pick_background() -> void:
	_bg_name = "bg_day" if rng.randf() < Config.day_chance() else "bg_night"
	for t in _bg_tiles:
		t.texture = Atlas.tex(_bg_name)
	_bg_top.texture = Atlas.strip(_bg_name, 0)


# ================================================================== layout (any aspect ratio)
func _layout() -> void:
	_view = get_viewport_rect().size
	var spare := maxf(_view.y - Config.GAME_H, 0.0)        # extra height this screen has beyond 512
	_lift = roundf(lift_frac * spare)
	var off := Vector2((_view.x - Config.GAME_W) * 0.5, _view.y - Config.GAME_H - _lift)
	world.position = off                              # bottom-centre anchoring, raised by _lift
	var extra_top := maxf(off.y, 0.0)
	var left := -off.x
	var right := _view.x - off.x

	pipes.left_limit = left
	pipes.right_limit = right
	pipes.top_extension = extra_top

	# background tiles cover [left, right]; a stretched 1-px sky row fills the extra height
	var first := floorf(left / Config.GAME_W) * Config.GAME_W
	for i in _bg_tiles.size():
		_bg_tiles[i].position = Vector2(first + i * Config.GAME_W, 0.0)
	_bg_top.position = Vector2(first, -extra_top - 8.0)
	_bg_top.scale = Vector2(float(_bg_tiles.size()), extra_top + 8.0)
	_place_ground()
	_layout_options(spare)


func _layout_options(spare: float) -> void:
	var win := Vector2(DisplayServer.window_get_size())
	var k := _view.x / maxf(win.x, 1.0)                   # window pixels -> view units
	var safe := DisplayServer.get_display_safe_area()
	var top := 0.0
	var right := 0.0
	if safe.size.x > 0 and win.x > 0:
		top = maxf(float(safe.position.y), 0.0) * k
		right = maxf(win.x - float(safe.end.x), 0.0) * k
	_opts.layout(_view, minf(top, 80.0), minf(right, 40.0), spare)


func _on_lift_changed(f: float) -> void:
	lift_frac = f
	_layout()


func _on_fps_changed(cap: bool) -> void:
	fps60 = cap
	_apply_fps()
	_save_best()


func _apply_fps() -> void:
	Engine.max_fps = 60 if fps60 else 0


func _place_ground() -> void:
	var left := -world.position.x
	var base := -_ground_x
	var first := floorf((left - base) / Config.LAND_W) * Config.LAND_W + base
	for i in _land_tiles.size():
		_land_tiles[i].position = Vector2(first + i * Config.LAND_W, float(Config.GROUND_Y))
		_fill[i].position = Vector2(first + i * Config.LAND_W, float(Config.GAME_H) - 1.0)
		_fill[i].scale = Vector2(1.0, _lift + 9.0)
		_fill[i].visible = _lift > 0.0


# ================================================================== audio
func _build_audio() -> void:
	for key in SFX_FILES:
		var p := AudioStreamPlayer.new()
		p.max_polyphony = 4
		var path: String = AUDIO_DIR + SFX_FILES[key]
		if ResourceLoader.exists(path):
			p.stream = load(path)
		add_child(p)
		_players[key] = p


func _sfx(key: String) -> void:
	var p: AudioStreamPlayer = _players.get(key)
	if p and p.stream:
		p.play()


# ================================================================== persistence
func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best = int(cf.get_value("score", "best", 0))
		scores.clear()
		for v in cf.get_value("scores", "top", []):
			scores.append(int(v))
		if scores.is_empty() and best > 0:
			scores.append(best)                        # carry over a pre-existing high score
		lift_frac = clampf(float(cf.get_value("options", "lift", 0.0)), 0.0, 1.0)
		fps60 = bool(cf.get_value("options", "fps60", false))


func _record_score() -> void:
	if score <= 0:
		return
	scores.append(score)
	scores.sort_custom(func(a: int, b: int) -> bool: return a > b)
	if scores.size() > LB_ROWS:
		scores.resize(LB_ROWS)
	_save_best()


func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.set_value("score", "best", best)
	cf.set_value("scores", "top", scores)
	cf.set_value("options", "lift", lift_frac)
	cf.set_value("options", "fps60", fps60)
	var err := cf.save(SAVE_PATH)
	if err != OK:
		push_warning("Could not save high score (error %d)" % err)


# ================================================================== delayed events
func _after(seconds: float, cb: Callable) -> void:
	_events.append([seconds, cb])


func _run_events(dt: float) -> void:
	var i := 0
	while i < _events.size():
		_events[i][0] -= dt
		if _events[i][0] <= 0.0:
			var cb: Callable = _events[i][1]
			_events.remove_at(i)
			cb.call()
		else:
			i += 1


# ================================================================== splash (original: 2 s ".GEARS" screen)
const SPLASH_PATH := "res://assets/gfx/splash.png"
const SPLASH_TIME := 2.0
const SPLASH_FADE := 0.3

func _build_splash() -> void:
	if not ResourceLoader.exists(SPLASH_PATH):
		return
	_splash_layer = CanvasLayer.new()
	_splash_layer.layer = 20
	add_child(_splash_layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.name = "Bg"
	_splash_layer.add_child(bg)
	var img := TextureRect.new()
	img.texture = load(SPLASH_PATH)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED   # image background is pure black, so it blends in
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splash_layer.add_child(img)
	_splash_left = SPLASH_TIME
	_splash_fade = SPLASH_FADE


func _step_splash(dt: float) -> void:
	if _splash_layer == null:
		return
	if _splash_left > 0.0:
		_splash_left = maxf(_splash_left - dt, 0.0)
	elif _splash_fade > 0.0:
		_splash_fade = maxf(_splash_fade - dt, 0.0)
		_splash_layer.get_child(0).modulate.a = _splash_fade / SPLASH_FADE
		_splash_layer.get_child(1).modulate.a = _splash_fade / SPLASH_FADE
		if _splash_fade <= 0.0:
			_splash_layer.queue_free()
			_splash_layer = null


# ================================================================== personal top-5 list
func _build_leaderboard(parent: Node) -> void:
	_lb = Node2D.new()
	_lb.position = Vector2(25.0, 110.0)
	_lb.visible = false
	parent.add_child(_lb)
	# original score panel, cut into label-free strips: top / stretchable middle / bottom
	_part("score_panel", Rect2i(0, 0, 238, 18), Vector2(0, 0))
	var mid := _part("score_panel", Rect2i(0, 14, 238, 1), Vector2(0, 18))
	mid.scale = Vector2(1.0, LB_H - 18.0 - 34.0)
	_part("score_panel", Rect2i(0, 92, 238, 34), Vector2(0, LB_H - 34.0))
	_part("score_panel", Rect2i(172, 60, 40, 14), Vector2(99, 26))          # the "BEST" label from the panel
	for i in LB_ROWS:
		var rank := Sprite2D.new()
		rank.centered = false
		rank.position = Vector2(34, 50 + i * 24)
		rank.texture = Atlas.tex("number_score_%02d" % (i + 1))
		_lb.add_child(rank)
		_lb_ranks.append(rank)
		var row := DigitRow.new()
		row.hud_font = false
		_lb.add_child(row)
		_lb_values.append(row)


func _part(sprite_name: String, r: Rect2i, pos: Vector2) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.centered = false
	sp.texture = Atlas.part(sprite_name, r)
	sp.position = pos
	_lb.add_child(sp)
	return sp


func _refresh_leaderboard() -> void:
	for i in LB_ROWS:
		var has := i < scores.size()
		_lb_ranks[i].visible = has
		_lb_values[i].visible = has
		if has:
			_lb_values[i].show_right(scores[i], 208.0, 50.0 + i * 24.0)
