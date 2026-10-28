class_name Options
extends CanvasLayer
## Title-screen options: a 3-bar button (top right) that opens a small panel cut from the
## original score panel. Everything lives in SCREEN space (288 x view_height units) so
## dragging the slider never moves under the finger while the playfield shifts.
##
##   HEIGHT      - raises the whole playfield (0 = original, bottom-anchored position)
##   FRAME RATE  - AUTO (display refresh rate) or capped at 60 for phones that stutter at 120 Hz

signal lift_changed(frac: float)     ## live while dragging
signal fps_changed(cap60: bool)
signal closed

const FONT_PATH := "res://assets/fonts/Silkscreen-Regular.ttf"
const PANEL_W := 238.0
const PANEL_H := 176.0
const BROWN := Color(85.0 / 255.0, 48.0 / 255.0, 0.0)
const LABEL := Color(252.0 / 255.0, 120.0 / 255.0, 88.0 / 255.0)    # salmon used by the original panel labels
const BORDER := Color(84.0 / 255.0, 56.0 / 255.0, 71.0 / 255.0)
const TRACK_X0 := 24.0
const TRACK_X1 := 214.0
const TRACK_Y := 84.0
const FPS_BTN := Rect2(138.0, 104.0, 76.0, 28.0)

var frac := 0.0
var cap60 := false
var spare := 0.0                      ## spare screen height in units; 0 disables the slider

var _view := Vector2(288, 512)
var _btn: Node2D                      # hamburger
var _btn_rect := Rect2()
var _btn_down := false
var _panel: Node2D
var _knob: Node2D
var _fps_text: Label
var _hint: Label
var _hint_r: Label
var _open := false
var _drag := false
var _pressed_fps := false
var _pressed_ok := false
var _ok: Sprite2D
var _font: Font


static func make_font() -> Font:
	var f: Font = null
	if ResourceLoader.exists(FONT_PATH):
		f = load(FONT_PATH)
	if f == null:
		f = ThemeDB.fallback_font
	return f


func _init() -> void:
	layer = 5


func _ready() -> void:
	_font = make_font()
	_build_button()
	_build_panel()
	_panel.visible = false
	set_button_visible(false)


func is_open() -> bool:
	return _open


func set_button_visible(v: bool) -> void:
	if _btn:
		_btn.visible = v and not _open


## Call whenever the viewport changes. Insets are in view units (notch / status bar).
func layout(view: Vector2, inset_top: float, inset_right: float, spare_height: float) -> void:
	_view = view
	spare = maxf(spare_height, 0.0)
	var bw := 34.0
	var bh := 28.0
	_btn_rect = Rect2(view.x - bw - 8.0 - inset_right, 8.0 + inset_top, bw, bh)
	if _btn:
		_btn.position = _btn_rect.position
		_panel.position = Vector2((view.x - PANEL_W) * 0.5, maxf(inset_top + 44.0, 52.0))
		_refresh()


func set_values(f: float, c60: bool) -> void:
	frac = clampf(f, 0.0, 1.0)
	cap60 = c60
	if _btn:
		_refresh()


# ------------------------------------------------------------------ build
func _slice(parent: Node, sprite: String, r: Rect2i, pos: Vector2, scale_: Vector2 = Vector2.ONE) -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.texture = Atlas.part(sprite, r)
	s.position = pos
	s.scale = scale_
	parent.add_child(s)
	return s


func _bar(parent: Node, r: Rect2, c: Color) -> void:
	var cr := ColorRect.new()
	cr.color = c
	cr.position = r.position
	cr.size = r.size
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cr)


## Orange button of any width, cut from the original button_ok art (caps + stretched middle).
func _orange(parent: Node, w: float) -> void:
	_slice(parent, "button_ok", Rect2i(0, 0, 10, 28), Vector2.ZERO)
	_slice(parent, "button_ok", Rect2i(14, 0, 1, 28), Vector2(10, 0), Vector2(w - 20.0, 1.0))
	_slice(parent, "button_ok", Rect2i(70, 0, 10, 28), Vector2(w - 10.0, 0))


func _build_button() -> void:
	_btn = Node2D.new()
	add_child(_btn)
	_orange(_btn, 34.0)
	for i in 3:                                           # three bars, white with the game's dark outline
		var y := 7.0 + i * 5.0
		_bar(_btn, Rect2(8, y - 1.0, 18, 5), BROWN)
		_bar(_btn, Rect2(9, y, 16, 3), Color.WHITE)


func _label(text: String, size: int, col: Color, pos: Vector2, w: float, align: int, outline: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(w, size + 4.0)
	l.horizontal_alignment = align as HorizontalAlignment
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline:
		l.add_theme_color_override("font_outline_color", BROWN)
		l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(l)
	return l


func _build_panel() -> void:
	_panel = Node2D.new()
	add_child(_panel)
	_slice(_panel, "score_panel", Rect2i(0, 0, 238, 18), Vector2.ZERO)
	_slice(_panel, "score_panel", Rect2i(0, 14, 238, 1), Vector2(0, 18), Vector2(1.0, PANEL_H - 18.0 - 34.0))
	_slice(_panel, "score_panel", Rect2i(0, 92, 238, 34), Vector2(0, PANEL_H - 34.0))

	_label("OPTIONS", 16, LABEL, Vector2(0, 18), PANEL_W, HORIZONTAL_ALIGNMENT_CENTER)
	_label("HEIGHT", 16, LABEL, Vector2(TRACK_X0, 46), 120.0, HORIZONTAL_ALIGNMENT_LEFT)
	# slider groove
	_bar(_panel, Rect2(TRACK_X0, TRACK_Y - 2.0, TRACK_X1 - TRACK_X0, 8), BROWN)
	_bar(_panel, Rect2(TRACK_X0 + 2.0, TRACK_Y, TRACK_X1 - TRACK_X0 - 4.0, 4), Color(1, 1, 1))
	_knob = Node2D.new()
	_panel.add_child(_knob)
	_orange(_knob, 20.0)
	_knob.position = Vector2(0, TRACK_Y - 12.0)
	_hint = _label("", 8, BORDER, Vector2(TRACK_X0, 96), TRACK_X1 - TRACK_X0, HORIZONTAL_ALIGNMENT_LEFT)
	_hint_r = _label("", 8, BORDER, Vector2(TRACK_X0, 96), TRACK_X1 - TRACK_X0, HORIZONTAL_ALIGNMENT_RIGHT)

	_label("FRAMES", 16, LABEL, Vector2(TRACK_X0, 106), 110.0, HORIZONTAL_ALIGNMENT_LEFT)
	var fb := Node2D.new()
	fb.position = FPS_BTN.position
	_panel.add_child(fb)
	_orange(fb, FPS_BTN.size.x)
	_fps_text = Label.new()
	_fps_text.position = Vector2(0, 5)
	_fps_text.size = Vector2(FPS_BTN.size.x, 20)
	_fps_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_text.add_theme_font_override("font", _font)
	_fps_text.add_theme_font_size_override("font_size", 16)
	_fps_text.add_theme_color_override("font_color", Color.WHITE)
	_fps_text.add_theme_color_override("font_outline_color", BROWN)
	_fps_text.add_theme_constant_override("outline_size", 4)
	_fps_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fb.add_child(_fps_text)

	_ok = Sprite2D.new()
	_ok.centered = false
	_ok.texture = Atlas.tex("button_ok")
	_ok.position = Vector2((PANEL_W - 80.0) * 0.5, PANEL_H - 40.0)
	_panel.add_child(_ok)


func _refresh() -> void:
	var enabled := spare >= 1.0
	_knob.position.x = TRACK_X0 + frac * (TRACK_X1 - TRACK_X0 - 20.0) + 0.0
	_knob.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.4)
	_hint.text = "LOW" if enabled else "NO SPARE HEIGHT"
	_hint_r.text = "HIGH" if enabled else ""
	_fps_text.text = "60 MAX" if cap60 else "AUTO"


# ------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			if _open:
				_press_open(p)
				get_viewport().set_input_as_handled()
			elif _btn.visible and _btn_rect.grow(6.0).has_point(p):
				_btn_down = true
				_btn.position = _btn_rect.position + Vector2(0, 2)
				get_viewport().set_input_as_handled()
		else:
			if _open:
				_release_open(p)
				get_viewport().set_input_as_handled()
			elif _btn_down:
				_btn_down = false
				_btn.position = _btn_rect.position
				if _btn_rect.grow(6.0).has_point(p):
					open()
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _open and _drag:
		_set_from_x(event.position.x - _panel.position.x)
		get_viewport().set_input_as_handled()


func open() -> void:
	_open = true
	_panel.visible = true
	_btn.visible = false
	_panel.modulate.a = 1.0
	_refresh()


func close() -> void:
	_open = false
	_drag = false
	_panel.visible = false
	_btn.visible = true
	closed.emit()


func _press_open(p: Vector2) -> void:
	var q := p - _panel.position
	_pressed_ok = false
	_pressed_fps = false
	if Rect2(TRACK_X0 - 14.0, TRACK_Y - 22.0, TRACK_X1 - TRACK_X0 + 28.0, 48.0).has_point(q) and spare >= 1.0:
		_drag = true
		_panel.modulate.a = 0.35                          # see-through while dragging so the result is visible
		_set_from_x(q.x)
	elif FPS_BTN.grow(4.0).has_point(q):
		_pressed_fps = true
	elif Rect2(_ok.position, Vector2(80, 28)).grow(8.0).has_point(q):
		_pressed_ok = true
		_ok.position.y += 2.0


func _release_open(p: Vector2) -> void:
	var q := p - _panel.position
	var was_drag := _drag
	if _drag:
		_drag = false
		_panel.modulate.a = 1.0
	if _pressed_fps:
		_pressed_fps = false
		if FPS_BTN.grow(4.0).has_point(q):
			cap60 = not cap60
			_refresh()
			fps_changed.emit(cap60)
	if _pressed_ok:
		_pressed_ok = false
		_ok.position.y = PANEL_H - 40.0
		if Rect2(_ok.position, Vector2(80, 28)).grow(8.0).has_point(q):
			close()
	elif not Rect2(Vector2.ZERO, Vector2(PANEL_W, PANEL_H)).has_point(q) and not _pressed_fps and not was_drag:
		close()                                           # tap outside the panel closes it


func _set_from_x(x: float) -> void:
	frac = clampf((x - TRACK_X0 - 10.0) / (TRACK_X1 - TRACK_X0 - 20.0), 0.0, 1.0)
	_refresh()
	lift_changed.emit(frac)
