class_name PipeManager
extends Node2D
## Scrolling pipe pairs: spawning, delta-time movement, scoring and collision.
##
## Original layout recovered from the APK:
##   * pair pitch 157 px (105 + 52), scroll 120 px/s  -> a new pair every 1.308 s
##   * lower pipe top edge  y = rand[180, 359]; upper pipe bottom = y - 96  (gap 96 px)
##   * pipe sprite 52x320, hit box = the whole sprite (no padding on the pipe side;
##     all of the forgiveness is the bird's 14 px sprite inset)
##   * a point is awarded the moment the pipe's LEFT edge reaches the bird's hit-box x (80)
##   * collision test is an INCLUSIVE AABB overlap (touching edges counts)

signal scored

## Pipes only move while true (Main stops it on death and before the first flap).
var scrolling: bool = false
var scroll_speed: float = Config.SCROLL_SPEED
## Visible world-space extents, so wider/taller screens never show pop-in.
var right_limit: float = float(Config.GAME_W)
var left_limit: float = 0.0
## Extra sky visible above y = 0 on tall (19.5:9) screens; the upper pipe is extended into it.
var top_extension: float = 0.0:
	set(value):
		top_extension = maxf(value, 0.0)
		for p in _pipes:
			_layout_pipe(p)

class Pipe:
	var x: float
	var gap_y: float          # y of the lower pipe's top edge (original `ad`)
	var scored: bool = false
	var node: Node2D
	var lower: Sprite2D
	var upper: Sprite2D
	var filler: Sprite2D      # 1-px body row stretched upward on tall screens

var rng := RandomNumberGenerator.new()

var _pipes: Array[Pipe] = []
var _pool: Array[Pipe] = []
var _next_x: float = Config.FIRST_PIPE_X

const SPAWN_MARGIN := Config.PIPE_SPACING + Config.PIPE_W


func _ready() -> void:
	rng.randomize()


func reset() -> void:
	for p in _pipes:
		p.node.visible = false
		_pool.append(p)
	_pipes.clear()
	_next_x = Config.FIRST_PIPE_X
	scrolling = false


func pipe_count() -> int:
	return _pipes.size()


func tick(dt: float) -> void:
	if not scrolling:
		return
	var dx := scroll_speed * dt
	_next_x -= dx
	for p in _pipes:
		p.x -= dx
		p.node.position.x = p.x
	while _next_x <= right_limit + SPAWN_MARGIN:
		_spawn(_next_x)
		_next_x += Config.PIPE_SPACING
	for p in _pipes:
		if not p.scored and p.x <= Config.BIRD_X:
			p.scored = true
			scored.emit()
	while not _pipes.is_empty() and _pipes[0].x + Config.PIPE_W < left_limit:
		var old: Pipe = _pipes.pop_front()
		old.node.visible = false
		_pool.append(old)


## Inclusive AABB test against every pipe (same comparison as the original).
func collides(r: Rect2) -> bool:
	for p in _pipes:
		if r.end.x < p.x or r.position.x > p.x + Config.PIPE_W:
			continue
		if _overlap(r, Rect2(p.x, p.gap_y, Config.PIPE_W, Config.PIPE_H)):
			return true
		if _overlap(r, Rect2(p.x, p.gap_y - Config.PIPE_GAP - Config.PIPE_H, Config.PIPE_W, Config.PIPE_H)):
			return true
	return false


static func _overlap(a: Rect2, b: Rect2) -> bool:
	return a.end.x >= b.position.x and a.position.x <= b.end.x \
		and a.end.y >= b.position.y and a.position.y <= b.end.y


func _spawn(at_x: float) -> void:
	var p: Pipe = _pool.pop_back() if not _pool.is_empty() else _make_pipe()
	p.x = at_x
	p.gap_y = float(rng.randi_range(Config.GAP_Y_MIN, Config.GAP_Y_MAX))
	p.scored = false
	p.node.visible = true
	p.node.position = Vector2(p.x, 0.0)
	_layout_pipe(p)
	_pipes.append(p)


func _make_pipe() -> Pipe:
	var p := Pipe.new()
	p.node = Node2D.new()
	p.lower = _sprite("pipe_up", p.node)
	p.upper = _sprite("pipe_down", p.node)
	p.filler = Sprite2D.new()
	p.filler.centered = false
	p.filler.texture = Atlas.strip("pipe_down", 0)   # row 0 of the upper pipe is plain body
	p.node.add_child(p.filler)
	add_child(p.node)
	return p


func _sprite(sprite_name: String, parent: Node) -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.texture = Atlas.tex(sprite_name)
	parent.add_child(s)
	return s


func _layout_pipe(p: Pipe) -> void:
	var upper_top := p.gap_y - Config.PIPE_GAP - Config.PIPE_H
	p.lower.position = Vector2(0.0, p.gap_y)
	p.upper.position = Vector2(0.0, upper_top)
	# On tall screens the sky above y=0 is visible: continue the pipe body up to the top.
	var fill_top := -top_extension - 16.0
	var fill_h := upper_top - fill_top
	p.filler.visible = fill_h > 0.0
	if p.filler.visible:
		p.filler.position = Vector2(0.0, fill_top)
		p.filler.scale = Vector2(1.0, fill_h)
