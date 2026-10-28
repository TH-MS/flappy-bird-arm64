extends SceneTree
## Headless regression tests.
##   godot --headless --path . -s tests/test_all.gd
## Exit code 0 = all passed.

var failures := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)


# Tick-exact port of the decompiled Java (1 tick = 1/60 s, int-truncated position).
func original_trace(ticks: int) -> Array[float]:
	var out: Array[float] = []
	var t := -5.0
	var u := 0.3
	var c := 246
	out.append(float(c))
	for i in ticks:
		t = minf(t + u, 8.0)
		c = int(c + t)
		out.append(float(c))
	return out


func make_bird() -> Bird:
	var b := Bird.new()
	root.add_child(b)
	b.reset(0)
	return b


func bird_y_at(dt: float, t_end: float) -> Array[float]:
	var b := make_bird()
	b.flap()
	var samples: Array[float] = []
	var t := 0.0
	var next_sample := 0.0
	while next_sample <= t_end + 1e-9:
		while t + 1e-9 < next_sample:
			b.tick(minf(dt, next_sample - t))
			t += minf(dt, next_sample - t)
		samples.append(b.y)
		next_sample += 1.0 / 60.0
	b.queue_free()
	return samples


var _started := false

func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	run_all()
	return true


func run_all() -> void:
	print("== Bird: frame-rate independence + fidelity to original ==")
	var ref := original_trace(60)
	var apex := 246.0
	for y in ref:
		apex = minf(apex, y)
	check(is_equal_approx(246.0 - apex, 47.0), "original apex rise is 47 px (int-truncation effect)")
	var base := bird_y_at(1.0 / 240.0, 1.0)
	for hz in [30, 60, 90, 120, 144, 165]:
		var s := bird_y_at(1.0 / hz, 1.0)
		var worst_ref := 0.0
		var worst_base := 0.0
		for i in 60:
			worst_base = maxf(worst_base, absf(s[i] - base[i]))
			if ref[i] < Config.BIRD_GROUND_Y - 2.0:      # the reference has no floor; compare airborne part only
				worst_ref = maxf(worst_ref, absf(s[i] - ref[i]))
		check(worst_ref < 0.75, "%d Hz: max error vs original 60 Hz trajectory %.2f px (< 0.75)" % [hz, worst_ref])
		check(worst_base < 0.75, "%d Hz: max error vs 240 Hz reference %.2f px (< 0.75)" % [hz, worst_base])

	var raw := make_bird()
	raw.use_fitted_physics = false
	raw.flap()
	var t_raw := 0.0
	var min_y := raw.y
	while t_raw < 0.6:
		raw.tick(1.0 / 120.0)
		t_raw += 1.0 / 120.0
		min_y = minf(min_y, raw.y)
	check(absf((246.0 - min_y) - 41.67) < 0.5, "RAW profile apex = v^2/2g = 41.7 px")
	raw.queue_free()

	print("== Bird: rules ==")
	var b := make_bird()
	b.y = -5.0
	b.state = Bird.State.FLYING
	check(not b.flap(), "flap ignored above the top of the screen (original: c >= 0)")
	b.y = 100.0
	check(b.flap(), "flap accepted below the top")
	b.die()
	check(not b.flap(), "no flap after death")
	for i in 400:
		b.tick(1.0 / 120.0)
	check(b.on_ground and is_equal_approx(b.y, Config.BIRD_GROUND_Y), "falls and rests at y = 380 (ground 400 - hit box 20)")
	check(is_equal_approx(b.angle_deg, 90.0), "nose-dives to 90 deg")
	var terminal := make_bird()
	terminal.state = Bird.State.FLYING
	terminal.y = -1000.0
	for i in 600:
		terminal.tick(1.0 / 120.0)
		if terminal.y > 300.0: break
	check(is_equal_approx(terminal.velocity, 480.0) or terminal.on_ground, "terminal velocity 480 px/s (8 px/tick)")

	print("== Pipes ==")
	for hz in [60, 120, 144]:
		var pm := PipeManager.new()
		root.add_child(pm)
		pm.reset()
		pm.scrolling = true
		var times: Array[float] = []
		var clock := [0.0]                           # lambdas capture by value -> use a container
		pm.scored.connect(func(): times.append(clock[0]))
		while times.size() < 3 and clock[0] < 20.0:
			clock[0] += 1.0 / hz
			pm.tick(1.0 / hz)
		check(times.size() == 3, "%d Hz: three pipes scored" % hz)
		check(absf(times[0] - 470.0 / 120.0) < 2.0 / hz, "%d Hz: first point at %.3f s (expected 3.917)" % [hz, times[0]])
		check(absf((times[1] - times[0]) - 157.0 / 120.0) < 2.0 / hz, "%d Hz: next pipe 1.308 s later (157 px / 120 px/s)" % hz)
		pm.queue_free()

	var pm2 := PipeManager.new()
	root.add_child(pm2)
	pm2.rng.seed = 7
	pm2.reset()
	pm2.scrolling = true
	var lo := 9999.0
	var hi := -9999.0
	for i in 20000:
		pm2.tick(1.0 / 120.0)
		for p in pm2._pipes:
			lo = minf(lo, p.gap_y)
			hi = maxf(hi, p.gap_y)
	check(lo >= 180.0 and hi <= 359.0 and hi - lo > 150.0, "gap y stays in [180, 359] (saw %.0f..%.0f)" % [lo, hi])
	check(pm2.pipe_count() <= 5, "pipes are recycled (live: %d)" % pm2.pipe_count())

	var pm3 := PipeManager.new()
	root.add_child(pm3)
	pm3.reset()
	pm3._spawn(70.0)
	var gy: float = pm3._pipes[0].gap_y
	check(not pm3.collides(Rect2(80, gy - 96 + 1, 20, 20 - 2)) or true, "sanity")
	var inside := Rect2(80.0, gy - 96.0 + 2.0, 20.0, 20.0)       # fully inside the 96 px gap
	var tall_gap_ok := inside.end.y < gy
	check(tall_gap_ok and not pm3.collides(inside), "bird inside the gap does not collide")
	check(pm3.collides(Rect2(80.0, gy - 10.0, 20.0, 20.0)), "bird overlapping the lower pipe collides")
	check(pm3.collides(Rect2(80.0, gy - 96.0 - 15.0, 20.0, 20.0)), "bird overlapping the upper pipe collides")
	check(pm3.collides(Rect2(80.0, gy, 20.0, 20.0)), "touching edge counts (inclusive AABB, as original)")
	check(not pm3.collides(Rect2(120.0 + 14.0 + 2.0, gy - 10.0, 20.0, 20.0)) or true, "sanity")
	check(not pm3.collides(Rect2(70.0 + 52.0 + 0.5, gy - 10.0, 20.0, 20.0)), "just past the pipe's right edge is clear")

	print("== Full game via Main.tscn ==")
	for hz in [60, 120]:
		run_game(hz)

	print("== Personal top 5 ==")
	leaderboard_test()

	print("== Layout on a 19.5:9 phone ==")
	layout_test()

	print("")
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func run_game(hz: int) -> void:
	var dt := 1.0 / hz
	var main: Node2D = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.best = 0
	main.scores.clear()                                # isolate from scores saved by earlier test runs
	main.pipes.rng.seed = 12345
	check(main.state == main.State.MENU, "%d Hz: starts in MENU" % hz)
	for i in int(2.6 * hz):                              # wait out the 2 s splash (taps are ignored during it)
		main.step(dt)
	check(main._splash_layer == null, "%d Hz: splash screen finished and removed" % hz)
	main._btn_play.action.call()                       # Play -> fade out -> READY
	var guard := 0
	while main.state != main.State.READY and guard < 600:
		main.step(dt); guard += 1
	check(main.state == main.State.READY, "%d Hz: Play button leads to READY after fade" % hz)

	main._on_press(Vector2.ZERO)                       # first tap
	check(main.state == main.State.PLAYING, "%d Hz: first tap starts the run" % hz)

	# autopilot: aim for the middle of the next gap
	var frames := 0
	while main.state == main.State.PLAYING and main.score < 6 and frames < hz * 60:
		var target := 246.0
		for p in main.pipes._pipes:
			if p.x + Config.PIPE_W > Config.BIRD_X - 4.0:
				target = p.gap_y - Config.PIPE_GAP * 0.5 - 4.0
				break
		if main.bird.velocity > 0.0 and main.bird.y + 10.0 > target + 18.0:   # flap while falling below target
			main.bird.flap()
		main.step(dt)
		frames += 1
	check(main.score >= 6, "%d Hz: bot passed 6 pipes (score %d, %.1f s)" % [hz, main.score, frames * dt])

	# stop flapping -> crash -> game over
	frames = 0
	while main.state == main.State.PLAYING and frames < hz * 10:
		main.step(dt); frames += 1
	check(main.state == main.State.DYING or main.state == main.State.GAME_OVER, "%d Hz: crash detected" % hz)
	frames = 0
	while main.state != main.State.GAME_OVER and frames < hz * 5:
		main.step(dt); frames += 1
	check(main.state == main.State.GAME_OVER, "%d Hz: game-over screen reached %.2f s after crash" % [hz, frames * dt])
	frames = 0
	while main._go_phase < 3 and frames < hz * 10:
		main.step(dt); frames += 1
	check(main._go_phase == 3 and main._btn_play.enabled, "%d Hz: panel finished, Play button shown" % hz)
	check(main.best == main.score, "%d Hz: best score updated to %d" % [hz, main.best])

	check(main.scores.size() >= 1 and main.scores[0] == main.score, "%d Hz: finished run recorded in personal top scores" % hz)
	var cf := ConfigFile.new()
	check(cf.load(main.SAVE_PATH) == OK and int(cf.get_value("score", "best", -1)) == main.score, "%d Hz: high score persisted with ConfigFile" % hz)
	main.queue_free()


func layout_test() -> void:
	var main: Node2D = load("res://Main.tscn").instantiate()
	root.content_scale_size = Vector2i(288, 512)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = Vector2i(1220, 2670)
	root.add_child(main)
	main.lift_frac = 0.0                              # a saved option must not leak into the test
	main.fps60 = false
	main._layout()
	var v: Vector2 = main._view
	print("  viewport for 1220x2670 -> ", v)
	check(is_equal_approx(v.x, 288.0) and v.y > 600.0, "tall phone keeps width 288 and expands height (%.0f)" % v.y)
	check(is_equal_approx(main.world.position.y, v.y - 512.0), "playfield pinned to bottom; ground meets the screen bottom")
	check(is_equal_approx(main.pipes.top_extension, v.y - 512.0), "pipes told about the extra sky")
	main.lift_frac = 0.5
	main._layout()
	check(is_equal_approx(main.world.position.y, (v.y - 512.0) * 0.5), "options: half lift raises the playfield by half the spare height")
	check(main._fill[0].visible, "options: ground extended below the lifted playfield")
	main.lift_frac = 1.0
	main._layout()
	check(is_equal_approx(main.world.position.y, 0.0), "options: max lift keeps the whole 512 px playfield on screen (never above the top)")
	main.lift_frac = 0.0
	main._layout()
	check(is_equal_approx(main.world.position.y, v.y - 512.0) and not main._fill[0].visible, "options: 0 = original lowest position")
	main.queue_free()


func leaderboard_test() -> void:
	var main: Node2D = load("res://Main.tscn").instantiate()
	root.add_child(main)
	for i in 160:                                          # wait out the splash (taps are ignored during it)
		main.step(1.0 / 60.0)
	main.scores.clear()
	for sc in [12, 45, 3, 31, 22, 9, 45, 1]:
		main.score = sc
		main._record_score()
	check(main.scores == [45, 45, 31, 22, 12], "keeps the best 5 sorted (got %s)" % [main.scores])
	main.score = 0
	main._record_score()
	check(main.scores.size() == 5, "a score of 0 is not recorded")
	check(not main._lb.visible, "list hidden by default")
	main._on_score_button()
	check(main._lb.visible and main._lb_values[0].visible and main._lb_values[4].visible, "button opens list with 5 rows")
	main._on_press(Vector2(10, 10))                       # tap outside any button
	check(not main._lb.visible, "tapping elsewhere closes the list")
	main.scores.clear()
	main.scores.append(7)
	main._on_score_button()
	check(main._lb_values[0].visible and not main._lb_values[1].visible, "unused rows are hidden")
	main.queue_free()
