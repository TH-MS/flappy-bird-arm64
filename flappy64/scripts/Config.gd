class_name Config
extends RefCounted
## Constants recovered from the Flappy Bird 1.3 Android build (com.dotgears.flappy).
##
## The original is TICK-based: every value below was an integer/float "per tick"
## quantity, and the engine ran a fixed 60 steps/s (AndEngine FixedStepEngine(…, 60)).
## They are stored here as PIXELS PER SECOND so they can be multiplied by the
## real frame delta. tick -> seconds: x_per_tick * 60 = x_per_second.

# ---- Logical playfield (original GL ortho = 288 x 512) -----------------------
const GAME_W := 288
const GAME_H := 512
const GROUND_Y := 400            # top edge of `land` sprite (512 - 112)
const LAND_W := 336              # `land` sprite width
const LAND_PERIOD := 24          # ground texture repeats every 24 px (original wrap)

# ---- Time base ---------------------------------------------------------------
const TICK_RATE := 60.0          # original fixed step rate
const MAX_DT := 1.0 / 30.0       # clamp for hitches / resume-from-pause

# ---- Bird --------------------------------------------------------------------
const BIRD_X := 80.0             # fixed hit-box x (left edge)
const BIRD_START_Y := 246.0      # hit-box y (top edge) while waiting
const BIRD_HIT_W := 20.0         # hit box 20x20 inside a 48x48 sprite
const BIRD_HIT_H := 20.0
const BIRD_SPRITE_INSET := 14.0  # (48 - 20) / 2
const BIRD_GROUND_Y := 380.0     # GROUND_Y - BIRD_HIT_H : bird.y >= this == crash

# Vertical motion. The Java code does, once per tick:
#     vy += 0.3 ; vy = min(vy, 8) ; y = (int)(y + vy)        // flap sets vy = -5
# Direct unit conversion (x60, x3600) is the "RAW" profile. Because the original
# truncates y to an int every tick, its real trajectory is ~12 px RMS away from that
# (apex 47 px, not 41.7 px; 9 px RMS / 13 px max error over a flap). The FITTED profile is
# a least-squares fit of the continuous model to the original tick trajectory:
# 0.22 px RMS, 0.54 px max, apex 47.2 px.
const JUMP_SPEED_RAW := 300.0        # 5.0 px/tick
const GRAVITY_RAW := 1080.0          # 0.3 px/tick^2
const TERMINAL_SPEED := 480.0        # 8.0 px/tick
const JUMP_SPEED_FITTED := 320.0
const GRAVITY_FITTED := 1085.0

# Rotation (degrees, +clockwise / nose-down): per tick  q += r ; r += 0.4 ; clamp(-20, 90); flap: r = -10
const ANGLE_MIN := -20.0
const ANGLE_MAX := 90.0
const ANGLE_VEL_FLAP := -600.0       # -10 deg/tick
const ANGLE_ACCEL := 1440.0          # 0.4 deg/tick^2

# Idle hover: y_offset = cos(phase) * 4, phase += 8 deg/tick
const BOB_AMPLITUDE := 4.0
const BOB_DEG_PER_SEC := 480.0

# Sprite animation timing (ticks / 60)
const FLAP_FRAME_TIME := 3.0 / 60.0  # 3 ticks per frame, 12-frame sequence, plays once per flap
const IDLE_FRAME_TIME := 7.0 / 60.0  # 7 ticks per frame, looping

# ---- Pipes / world scroll ----------------------------------------------------
const SCROLL_SPEED := 120.0      # 2 px/tick (pipes AND ground)
const PIPE_W := 52.0
const PIPE_H := 320.0
const PIPE_GAP := 96.0           # vertical opening between the two pipes
const PIPE_SPACING := 157.0      # left-edge to left-edge: 105 + 52 = 157 px (1.308 s)
const GAP_Y_MIN := 180           # random y of the LOWER pipe's top edge, inclusive
const GAP_Y_MAX := 359           # (Java: 180 + rand % 180)
const FIRST_PIPE_X := 550.0      # x at the moment of the first flap (pipe is on screen ~3.7 s later)

# ---- UI timings (seconds) ----------------------------------------------------
const FLASH_TIME := 1.0          # white flash, alpha = (1 - t)^5
const FADE_TIME := 0.5
const DIE_SOUND_DELAY := 0.2833  # 17 ticks (only after a PIPE hit)
const GAME_OVER_DELAY := 0.5667  # 34 ticks
const MEDAL_THRESHOLDS := [40, 30, 20, 10]  # medals_0 (platinum) .. medals_3 (bronze)

static func day_chance() -> float:
	return 0.6   # original: bg_day if rand % 10 > 3
