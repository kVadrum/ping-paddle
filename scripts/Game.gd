## Game.gd — Core game loop, physics, AI, and procedural rendering
##
## Owns all gameplay state: ball, paddles, scoring, and the playing field.
## Renders everything procedurally via _draw() — no sprites, no textures.
## Communicates state changes to Main.gd via signals.

extends Node2D

# ─── Signals ─────────────────────────────────────────────────────────────────
## Emitted whenever either player's score changes.
signal score_changed(p1_score: int, p2_score: int)
## Emitted to show or clear the win banner (empty string = clear).
signal banner_changed(text: String)

# ─── Tuning Constants ────────────────────────────────────────────────────────
## These define the base feel of the game at challenge=1.0.
## All speed values scale with the challenge multiplier.

const BASE_BALL_SPEED     := 360.0   ## Initial horizontal ball speed (px/s)
const BASE_BALL_Y_RANGE   := 240.0   ## Max initial vertical speed on serve
const MAX_BALL_SPEED      := 1400.0  ## Absolute speed cap to prevent tunneling
const BALL_RADIUS         := 9.0     ## Ball radius in pixels
const HIT_ACCEL           := 1.03    ## Speed multiplier per paddle hit (base)
const HIT_ACCEL_CHALLENGE := 0.02    ## Extra accel per challenge level above 1

const BASE_PADDLE_SPEED   := 520.0   ## Paddle movement speed (px/s)
const BASE_PADDLE_SIZE    := Vector2(16, 100)  ## Default paddle dimensions
const PADDLE_MARGIN       := 36.0    ## Distance from field edge to paddle face

const SERVE_DELAY         := 0.7     ## Seconds to pause before serving the ball

const WINNING_SCORE       := 7       ## Points needed to win a match

const TRAIL_LENGTH        := 18      ## Max trail dots behind the ball

# ─── AI Tuning ───────────────────────────────────────────────────────────────
## AI difficulty (1.0–3.0) interpolates between these min/max values.
const AI_INTERVAL_EASY    := 0.25    ## Reaction interval at difficulty 1 (slow)
const AI_INTERVAL_HARD    := 0.05    ## Reaction interval at difficulty 3 (fast)
const AI_NOISE_EASY       := 220.0   ## Y-axis noise at difficulty 1 (inaccurate)
const AI_NOISE_HARD       := 20.0    ## Y-axis noise at difficulty 3 (precise)
const AI_SPEED_EASY       := 0.55    ## Paddle speed multiplier at difficulty 1
const AI_SPEED_HARD       := 1.7     ## Paddle speed multiplier at difficulty 3
const AI_DEADZONE_EASY    := 70.0    ## Movement deadzone at difficulty 1 (lazy)
const AI_DEADZONE_HARD    := 8.0     ## Movement deadzone at difficulty 3 (snappy)

# ─── Sound Constants ─────────────────────────────────────────────────────────
## Procedural beep parameters — no audio files needed.
const SFX_SAMPLE_RATE     := 22050
const SFX_PADDLE_HIT_HZ   := 440.0   ## A4 — crisp paddle hit
const SFX_WALL_BOUNCE_HZ  := 330.0   ## E4 — softer wall bounce
const SFX_SCORE_HZ        := 220.0   ## A3 — low tone on score
const SFX_PADDLE_HIT_DUR  := 0.06    ## Duration in seconds
const SFX_WALL_BOUNCE_DUR := 0.04
const SFX_SCORE_DUR       := 0.15

# ─── Game State ──────────────────────────────────────────────────────────────

var paddle_size   := BASE_PADDLE_SIZE  ## Current paddle size (may be scaled)
var paddle_speed  := BASE_PADDLE_SPEED ## Current paddle speed (scales with challenge)
var field_size    : Vector2            ## Playable area (viewport minus bottom bar)
var bottom_margin := 56.0             ## Reserved space for the HUD bottom bar

var ball_pos := Vector2.ZERO  ## Current ball center position
var ball_vel := Vector2.ZERO  ## Current ball velocity (px/s)

var p1_y := 0.0  ## Player 1 paddle center Y
var p2_y := 0.0  ## Player 2 paddle center Y

var p1_score := 0
var p2_score := 0
var game_over := false

var challenge    := 1.0   ## Speed/difficulty multiplier (1.0–3.0)
var ai_enabled   := false ## Whether Player 2 is AI-controlled
var ai_difficulty := 1.0  ## AI skill level (1.0–3.0)

# ─── Serve Delay ─────────────────────────────────────────────────────────────
var _serve_timer     := 0.0   ## Countdown before ball launches
var _serving         := false ## True while waiting to serve
var _serve_direction := 1     ## Which direction to launch (+1 = right, -1 = left)

# ─── AI Internal State ───────────────────────────────────────────────────────
var _ai_timer    := 0.0   ## Time until next AI reaction
var _ai_interval := 0.2   ## Current reaction interval
var _ai_target_y := 0.0   ## Where the AI is trying to move

# ─── Trail ───────────────────────────────────────────────────────────────────
var trail := PackedVector2Array()

# ─── Theme Colors ────────────────────────────────────────────────────────────
var dark_mode  := true
var bg_color   := Color(0.25, 0.25, 0.25)  ## Field background
var fg_color   := Color(1, 1, 1)            ## Paddles, ball, text
var line_color := Color(0.5, 0.5, 0.5)      ## Center line dashes

# ─── Score Flash ──────────────────────────────────────────────────────────────
## Brief white/dark flash when a point is scored, for visual impact.
var _flash_alpha := 0.0

# ─── Audio Players ───────────────────────────────────────────────────────────
## Created once in _ready(), reused for all sound effects.
var _sfx_paddle : AudioStreamPlayer
var _sfx_wall   : AudioStreamPlayer
var _sfx_score  : AudioStreamPlayer


# ══════════════════════════════════════════════════════════════════════════════
#  INITIALIZATION
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Pause-aware: this node freezes when the scene tree is paused,
	# so the game loop stops during pause/title screen automatically.
	process_mode = Node.PROCESS_MODE_PAUSABLE

	_refresh_field_size()
	_center_paddles()
	_start_serve(1)
	trail.clear()

	# Generate procedural sound effects
	_sfx_paddle = _make_beep_player(SFX_PADDLE_HIT_HZ, SFX_PADDLE_HIT_DUR)
	_sfx_wall   = _make_beep_player(SFX_WALL_BOUNCE_HZ, SFX_WALL_BOUNCE_DUR)
	_sfx_score  = _make_beep_player(SFX_SCORE_HZ, SFX_SCORE_DUR)


# ══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API — called by Main.gd to push settings into the game
# ══════════════════════════════════════════════════════════════════════════════

func set_bottom_margin(h: float) -> void:
	bottom_margin = h
	handle_resized()

func set_challenge(v: float) -> void:
	## Adjusts game speed. Scales ball velocity, paddle speed, and serve speed.
	challenge = clamp(v, 1.0, 3.0)
	# Paddle speed scales modestly so players can keep up
	paddle_speed = BASE_PADDLE_SPEED * lerp(1.0, 1.35, (challenge - 1.0) / 2.0)
	# Rescale ball velocity to match new challenge (preserve direction)
	if ball_vel.length() > 0.0:
		ball_vel = ball_vel.normalized() * (BASE_BALL_SPEED * challenge)

func set_paddle_scale(v: float) -> void:
	## Adjusts paddle height. Larger paddles = easier rallies.
	var s: float = clamp(v, 1.0, 3.0)
	paddle_size = Vector2(BASE_PADDLE_SIZE.x, BASE_PADDLE_SIZE.y * s)

func set_ai_enabled(on: bool) -> void:
	ai_enabled = on

func set_ai_difficulty(v: float) -> void:
	ai_difficulty = clamp(v, 1.0, 3.0)

func set_dark_mode(on: bool) -> void:
	## Switches the field between dark and light color schemes.
	dark_mode = on
	if dark_mode:
		bg_color   = Color(0.25, 0.25, 0.25)
		fg_color   = Color(1, 1, 1)
		line_color = Color(0.5, 0.5, 0.5)
	else:
		bg_color   = Color(0.92, 0.92, 0.92)
		fg_color   = Color(0.1, 0.1, 0.1)
		line_color = Color(0.65, 0.65, 0.65)
	queue_redraw()


# ══════════════════════════════════════════════════════════════════════════════
#  GAME LOOP
# ══════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	# When the match is over, nothing moves — no need to process.
	if game_over:
		return

	_handle_input(delta)

	# Serve delay: ball sits at center, paddles can move, then ball launches.
	if _serving:
		_serve_timer -= delta
		if _serve_timer <= 0.0:
			_launch_ball()
	else:
		_update_ball(delta)

	# Fade out the score flash
	if _flash_alpha > 0.0:
		_flash_alpha = max(0.0, _flash_alpha - delta * 4.0)

	# Build the trail behind the ball
	trail.append(ball_pos)
	if trail.size() > TRAIL_LENGTH:
		trail.remove_at(0)

	queue_redraw()


# ══════════════════════════════════════════════════════════════════════════════
#  FIELD & LAYOUT
# ══════════════════════════════════════════════════════════════════════════════

func handle_resized() -> void:
	## Called by Main.gd when the viewport size changes.
	_refresh_field_size()
	# Keep paddles within bounds after resize
	var half: float = paddle_size.y * 0.5
	p1_y = clamp(p1_y, half, field_size.y - half)
	p2_y = clamp(p2_y, half, field_size.y - half)
	queue_redraw()

func _refresh_field_size() -> void:
	## Recalculates the playable area from the viewport, minus the bottom bar.
	## Guards against zero-size viewports (happens briefly during minimize).
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return
	field_size = Vector2(vp.x, max(1.0, vp.y - bottom_margin))

func _center_paddles() -> void:
	p1_y = field_size.y * 0.5
	p2_y = field_size.y * 0.5


# ══════════════════════════════════════════════════════════════════════════════
#  INPUT
# ══════════════════════════════════════════════════════════════════════════════

func _handle_input(delta: float) -> void:
	# Player 1: W/S keys
	if Input.is_key_pressed(KEY_W):
		p1_y -= paddle_speed * delta
	if Input.is_key_pressed(KEY_S):
		p1_y += paddle_speed * delta

	# Player 2: O/L keys, or AI
	if ai_enabled:
		_ai_move_p2(delta)
	else:
		if Input.is_key_pressed(KEY_O):
			p2_y -= paddle_speed * delta
		if Input.is_key_pressed(KEY_L):
			p2_y += paddle_speed * delta

	# Clamp both paddles to the field
	var half: float = paddle_size.y * 0.5
	p1_y = clamp(p1_y, half, field_size.y - half)
	p2_y = clamp(p2_y, half, field_size.y - half)


# ══════════════════════════════════════════════════════════════════════════════
#  AI OPPONENT
# ══════════════════════════════════════════════════════════════════════════════

func _ai_move_p2(delta: float) -> void:
	## AI for Player 2. Periodically picks a target Y based on ball position
	## (with noise for imperfection), then moves toward it.
	## At high difficulty, predicts where the ball will arrive at the paddle.
	_ai_timer -= delta
	_ai_interval = lerp(AI_INTERVAL_EASY, AI_INTERVAL_HARD,
		(ai_difficulty - 1.0) / 2.0)

	if _ai_timer <= 0.0:
		_ai_timer = _ai_interval

		# Predict where ball will reach P2's paddle X position
		var target_y: float = _ai_predict_y() if ai_difficulty >= 2.0 else ball_pos.y

		# Add noise — less noise at higher difficulty for tighter tracking
		var noise_range: float = lerp(AI_NOISE_EASY, AI_NOISE_HARD,
			(ai_difficulty - 1.0) / 2.0)
		var noise: float = noise_range * (randf() * 2.0 - 1.0)
		_ai_target_y = clamp(target_y + noise, 0.0, field_size.y)

	# Move toward target with speed proportional to difficulty
	var max_speed: float = paddle_speed * lerp(AI_SPEED_EASY, AI_SPEED_HARD,
		(ai_difficulty - 1.0) / 2.0)
	var dy: float = _ai_target_y - p2_y

	# Dead zone — don't jitter when close enough
	var deadzone: float = lerp(AI_DEADZONE_EASY, AI_DEADZONE_HARD,
		(ai_difficulty - 1.0) / 2.0)
	if abs(dy) < deadzone:
		return

	p2_y += clamp(dy, -max_speed * delta, max_speed * delta)

func _ai_predict_y() -> float:
	## Simple linear prediction: projects the ball's trajectory to the
	## P2 paddle's X position, bouncing off top/bottom walls.
	## Returns the predicted Y where the ball will arrive.
	if ball_vel.x <= 0.0:
		# Ball is moving away from P2 — just track current Y
		return ball_pos.y

	var paddle_x: float = field_size.x - PADDLE_MARGIN - paddle_size.x
	var dx: float = paddle_x - ball_pos.x
	if dx <= 0.0:
		return ball_pos.y

	# Time for ball to reach paddle
	var t: float = dx / ball_vel.x
	# Predicted raw Y (may be outside field)
	var raw_y: float = ball_pos.y + ball_vel.y * t

	# Simulate wall bounces by "folding" the Y position back into the field
	# using modular arithmetic on a reflected coordinate system
	var h: float = field_size.y - BALL_RADIUS * 2.0
	if h <= 0.0:
		return ball_pos.y
	var adjusted: float = raw_y - BALL_RADIUS
	# Number of full reflections
	var periods: int = int(abs(adjusted) / h)
	var remainder: float = fmod(abs(adjusted), h)
	if adjusted < 0.0:
		periods += 1
		remainder = h - remainder

	# Odd number of reflections means we're on a return bounce
	if periods % 2 == 1:
		return (h - remainder) + BALL_RADIUS
	else:
		return remainder + BALL_RADIUS


# ══════════════════════════════════════════════════════════════════════════════
#  BALL PHYSICS
# ══════════════════════════════════════════════════════════════════════════════

func _start_serve(direction: int) -> void:
	## Places the ball at center and starts the serve countdown.
	ball_pos = field_size * 0.5
	ball_vel = Vector2.ZERO
	_serve_direction = direction
	_serve_timer = SERVE_DELAY
	_serving = true
	trail.clear()

func _launch_ball() -> void:
	## Fires the ball after the serve delay expires.
	_serving = false
	ball_vel = Vector2(
		BASE_BALL_SPEED * _serve_direction,
		randf_range(-BASE_BALL_Y_RANGE, BASE_BALL_Y_RANGE)
	) * challenge

func _update_ball(delta: float) -> void:
	## Moves the ball, handles wall bounces, paddle collisions, and scoring.
	ball_pos += ball_vel * delta

	# ── Wall bounces (top and bottom) ────────────────────────────────────
	if (ball_pos.y - BALL_RADIUS) <= 0.0:
		ball_pos.y = BALL_RADIUS
		ball_vel.y = abs(ball_vel.y)
		_sfx_wall.play()
	elif (ball_pos.y + BALL_RADIUS) >= field_size.y:
		ball_pos.y = field_size.y - BALL_RADIUS
		ball_vel.y = -abs(ball_vel.y)
		_sfx_wall.play()

	# ── Paddle collision rects ───────────────────────────────────────────
	var p1_rect := Rect2(
		Vector2(PADDLE_MARGIN, p1_y - paddle_size.y * 0.5),
		paddle_size)
	var p2_rect := Rect2(
		Vector2(field_size.x - PADDLE_MARGIN - paddle_size.x,
			p2_y - paddle_size.y * 0.5),
		paddle_size)
	var ball_rect := Rect2(
		ball_pos - Vector2(BALL_RADIUS, BALL_RADIUS),
		Vector2(BALL_RADIUS * 2.0, BALL_RADIUS * 2.0))

	# ── Player 1 paddle hit ─────────────────────────────────────────────
	if p1_rect.intersects(ball_rect) and ball_vel.x < 0.0:
		ball_pos.x = p1_rect.position.x + p1_rect.size.x + BALL_RADIUS
		var accel: float = HIT_ACCEL + HIT_ACCEL_CHALLENGE * (challenge - 1.0)
		ball_vel.x = abs(ball_vel.x) * accel
		# Angle the return based on where the ball hit the paddle
		var offset: float = (ball_pos.y - (p1_rect.position.y + p1_rect.size.y * 0.5)) \
			/ (paddle_size.y * 0.5)
		ball_vel.y = clamp(
			ball_vel.y + offset * (200.0 * challenge),
			-600.0 * challenge, 600.0 * challenge)
		_clamp_ball_speed()
		_sfx_paddle.play()

	# ── Player 2 paddle hit ─────────────────────────────────────────────
	elif p2_rect.intersects(ball_rect) and ball_vel.x > 0.0:
		ball_pos.x = p2_rect.position.x - BALL_RADIUS
		var accel: float = HIT_ACCEL + HIT_ACCEL_CHALLENGE * (challenge - 1.0)
		ball_vel.x = -abs(ball_vel.x) * accel
		var offset: float = (ball_pos.y - (p2_rect.position.y + p2_rect.size.y * 0.5)) \
			/ (paddle_size.y * 0.5)
		ball_vel.y = clamp(
			ball_vel.y + offset * (200.0 * challenge),
			-600.0 * challenge, 600.0 * challenge)
		_clamp_ball_speed()
		_sfx_paddle.play()

	# ── Scoring: ball passes left or right edge ─────────────────────────
	if ball_pos.x < -BALL_RADIUS:
		p2_score += 1
		_emit_score()
		_sfx_score.play()
		_flash_alpha = 0.35  # Brief screen flash for impact
		_check_win()
		if not game_over:
			_start_serve(1)  # Serve toward the scorer's opponent
	elif ball_pos.x > field_size.x + BALL_RADIUS:
		p1_score += 1
		_emit_score()
		_sfx_score.play()
		_flash_alpha = 0.35
		_check_win()
		if not game_over:
			_start_serve(-1)

func _clamp_ball_speed() -> void:
	## Prevents the ball from exceeding MAX_BALL_SPEED, which would cause
	## it to tunnel through paddles (moving more than paddle width per frame).
	if ball_vel.length() > MAX_BALL_SPEED:
		ball_vel = ball_vel.normalized() * MAX_BALL_SPEED


# ══════════════════════════════════════════════════════════════════════════════
#  SCORING
# ══════════════════════════════════════════════════════════════════════════════

func _emit_score() -> void:
	score_changed.emit(p1_score, p2_score)

func _check_win() -> void:
	if p1_score >= WINNING_SCORE:
		game_over = true
		ball_vel = Vector2.ZERO
		banner_changed.emit("Player 1 Wins!\nPress R to Restart")
	elif p2_score >= WINNING_SCORE:
		game_over = true
		ball_vel = Vector2.ZERO
		banner_changed.emit("Player 2 Wins!\nPress R to Restart")

func reset_match() -> void:
	## Resets scores and starts a fresh match.
	p1_score = 0
	p2_score = 0
	game_over = false
	_emit_score()
	banner_changed.emit("")
	_start_serve(1)


# ══════════════════════════════════════════════════════════════════════════════
#  PROCEDURAL RENDERING
# ══════════════════════════════════════════════════════════════════════════════

func _draw() -> void:
	## All visuals are drawn here — no sprites, no textures, just geometry.
	## This runs every frame via queue_redraw() in _process().

	# Background fill
	draw_rect(Rect2(Vector2.ZERO, field_size), bg_color)

	# Center court dashed line
	var dash_h: float = 16.0
	var gap: float    = 12.0
	var center_x: float = field_size.x * 0.5
	var y: float = 0.0
	while y < field_size.y:
		draw_rect(Rect2(Vector2(center_x - 2.0, y), Vector2(4.0, dash_h)), line_color)
		y += dash_h + gap

	# Paddles
	var p1_pos := Vector2(PADDLE_MARGIN, p1_y - paddle_size.y * 0.5)
	var p2_pos := Vector2(field_size.x - PADDLE_MARGIN - paddle_size.x,
		p2_y - paddle_size.y * 0.5)
	draw_rect(Rect2(p1_pos, paddle_size), fg_color)
	draw_rect(Rect2(p2_pos, paddle_size), fg_color)

	# Ball trail — fades from transparent (oldest) to semi-opaque (newest)
	var n: int = trail.size()
	for i in range(n):
		var t: float = float(i) / float(max(1, n - 1))  # 0=oldest, 1=newest
		var alpha: float = lerp(0.1, 0.6, t)
		var radius: float = BALL_RADIUS * lerp(0.5, 1.0, t)
		draw_circle(trail[i], radius, Color(fg_color, alpha))

	# Ball
	draw_circle(ball_pos, BALL_RADIUS, fg_color)

	# Score flash overlay — brief white/dark pulse on point scored
	if _flash_alpha > 0.0:
		var flash_color := Color(1, 1, 1, _flash_alpha) if dark_mode \
			else Color(0, 0, 0, _flash_alpha)
		draw_rect(Rect2(Vector2.ZERO, field_size), flash_color)


# ══════════════════════════════════════════════════════════════════════════════
#  PROCEDURAL AUDIO
# ══════════════════════════════════════════════════════════════════════════════

func _make_beep_player(hz: float, duration: float) -> AudioStreamPlayer:
	## Generates a short sine-wave beep and wraps it in an AudioStreamPlayer.
	## This gives us retro Pong sound effects with zero asset files.
	var samples: int = int(SFX_SAMPLE_RATE * duration)
	var audio := AudioStreamWAV.new()
	audio.mix_rate = SFX_SAMPLE_RATE
	audio.format = AudioStreamWAV.FORMAT_8_BITS
	audio.stereo = false

	var data := PackedByteArray()
	data.resize(samples)
	for i in range(samples):
		# Sine wave with a quick linear fade-out to avoid clicks
		var t: float = float(i) / float(samples)
		var envelope: float = 1.0 - t  # Linear decay
		var sample: float = sin(TAU * hz * float(i) / SFX_SAMPLE_RATE) * envelope
		# Convert float [-1, 1] to unsigned byte [0, 255]
		data[i] = int((sample * 0.5 + 0.5) * 255.0)
	audio.data = data

	var player := AudioStreamPlayer.new()
	player.stream = audio
	player.volume_db = -12.0  # Subtle — not jarring
	player.bus = "Master"
	add_child(player)
	return player
