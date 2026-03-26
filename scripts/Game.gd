extends Node2D

var base_paddle_size := Vector2(16, 100)
var paddle_size := Vector2(16, 100)
var paddle_margin := 36.0
var paddle_speed := 520.0

var field_size: Vector2
var bottom_margin := 56.0

var ball_pos := Vector2.ZERO
var ball_vel := Vector2(360, 240)
var ball_radius := 9.0

var p1_y := 0.0
var p2_y := 0.0

var p1_score := 0
var p2_score := 0
var winning_score := 7
var game_over := false

var challenge := 1.0
var ai_enabled := false
var ai_difficulty := 1.0

var _set_score := Callable()
var _set_banner := Callable()

var trail := PackedVector2Array()
var trail_max := 18

var dark_mode := true
var bg_color := Color(0.25, 0.25, 0.25)
var fg_color := Color(1, 1, 1)
var line_color := Color(0.5, 0.5, 0.5)

func set_score_callback(cb: Callable) -> void:
	_set_score = cb
	_emit_score()

func set_banner_callback(cb: Callable) -> void:
	_set_banner = cb

func set_bottom_margin(h: float) -> void:
	bottom_margin = h
	handle_resized()

func set_challenge(v: float) -> void:
	challenge = clamp(v, 1.0, 3.0)
	paddle_speed = 520.0 * lerp(1.0, 1.35, (challenge - 1.0) / 2.0)
	if ball_vel.length() > 0.0:
		ball_vel = ball_vel.normalized() * (360.0 * challenge)

func set_paddle_scale(v: float) -> void:
	var s = clamp(v, 1.0, 3.0)
	paddle_size = Vector2(base_paddle_size.x, base_paddle_size.y * s)

func set_ai_enabled(on: bool) -> void:
	ai_enabled = on

func set_ai_difficulty(v: float) -> void:
	ai_difficulty = clamp(v, 1.0, 3.0)

func set_dark_mode(on: bool) -> void:
	dark_mode = on
	if dark_mode:
		bg_color = Color(0.25, 0.25, 0.25)
		fg_color = Color(1, 1, 1)
		line_color = Color(0.5, 0.5, 0.5)
	else:
		bg_color = Color(0.92, 0.92, 0.92)
		fg_color = Color(0.1, 0.1, 0.1)
		line_color = Color(0.65, 0.65, 0.65)
	queue_redraw()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_refresh_field_size()
	_center_paddles()
	reset_round()
	trail.clear()

func handle_resized() -> void:
	_refresh_field_size()
	var half := paddle_size.y * 0.5
	p1_y = clamp(p1_y, half, field_size.y - half)
	p2_y = clamp(p2_y, half, field_size.y - half)
	queue_redraw()

func _process(delta: float) -> void:
	if game_over:
		queue_redraw()
		return
	_handle_input(delta)
	_update_ball(delta)
	trail.append(ball_pos)
	if trail.size() > trail_max:
		trail.remove_at(0)
	queue_redraw()

func _refresh_field_size() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return
	field_size = Vector2(vp.x, max(1.0, vp.y - bottom_margin))

func _center_paddles() -> void:
	p1_y = field_size.y * 0.5
	p2_y = field_size.y * 0.5

func _handle_input(delta: float) -> void:
	if Input.is_key_pressed(KEY_W):
		p1_y -= paddle_speed * delta
	if Input.is_key_pressed(KEY_S):
		p1_y += paddle_speed * delta
	if ai_enabled:
		_ai_move_p2(delta)
	else:
		if Input.is_key_pressed(KEY_O):
			p2_y -= paddle_speed * delta
		if Input.is_key_pressed(KEY_L):
			p2_y += paddle_speed * delta
	var half := paddle_size.y * 0.5
	p1_y = clamp(p1_y, half, field_size.y - half)
	p2_y = clamp(p2_y, half, field_size.y - half)

var _ai_timer := 0.0
var _ai_interval := 0.2
var _ai_target_y := 0.0

func _ai_move_p2(delta: float) -> void:
	_ai_timer -= delta
	_ai_interval = lerp(0.25, 0.05, (ai_difficulty - 1.0) / 2.0)
	if _ai_timer <= 0.0:
		_ai_timer = _ai_interval
		var noise: float = lerp(220.0, 20.0, (ai_difficulty - 1.0) / 2.0) * (randf() * 2.0 - 1.0)
		_ai_target_y = clamp(ball_pos.y + noise, 0.0, field_size.y)
	var max_speed: float = paddle_speed * lerp(0.55, 1.7, (ai_difficulty - 1.0) / 2.0)
	var dy := _ai_target_y - p2_y
	var dz: float = lerp(70.0, 8.0, (ai_difficulty - 1.0) / 2.0)
	if abs(dy) < dz:
		return
	p2_y += clamp(dy, -max_speed * delta, max_speed * delta)

func _update_ball(delta: float) -> void:
	ball_pos += ball_vel * delta
	if (ball_pos.y - ball_radius) <= 0.0:
		ball_pos.y = ball_radius
		ball_vel.y = abs(ball_vel.y)
	elif (ball_pos.y + ball_radius) >= field_size.y:
		ball_pos.y = field_size.y - ball_radius
		ball_vel.y = -abs(ball_vel.y)
	var p1_rect := Rect2(Vector2(paddle_margin, p1_y - paddle_size.y * 0.5), paddle_size)
	var p2_rect := Rect2(Vector2(field_size.x - paddle_margin - paddle_size.x, p2_y - paddle_size.y * 0.5), paddle_size)
	var brect := Rect2(ball_pos - Vector2(ball_radius, ball_radius), Vector2(ball_radius * 2.0, ball_radius * 2.0))
	if p1_rect.intersects(brect) and ball_vel.x < 0.0:
		ball_pos.x = p1_rect.position.x + p1_rect.size.x + ball_radius
		ball_vel.x = abs(ball_vel.x) * (1.03 + 0.02 * (challenge - 1.0))
		var offset := (ball_pos.y - (p1_rect.position.y + p1_rect.size.y * 0.5)) / (paddle_size.y * 0.5)
		ball_vel.y = clamp(ball_vel.y + offset * (200.0 * challenge), -600.0 * challenge, 600.0 * challenge)
	elif p2_rect.intersects(brect) and ball_vel.x > 0.0:
		ball_pos.x = p2_rect.position.x - ball_radius
		ball_vel.x = -abs(ball_vel.x) * (1.03 + 0.02 * (challenge - 1.0))
		var offset2 := (ball_pos.y - (p2_rect.position.y + p2_rect.size.y * 0.5)) / (paddle_size.y * 0.5)
		ball_vel.y = clamp(ball_vel.y + offset2 * (200.0 * challenge), -600.0 * challenge, 600.0 * challenge)
	if ball_pos.x < -ball_radius:
		p2_score += 1
		_emit_score()
		_check_win()
		if not game_over:
			reset_round(1)
	elif ball_pos.x > field_size.x + ball_radius:
		p1_score += 1
		_emit_score()
		_check_win()
		if not game_over:
			reset_round(-1)

func _emit_score() -> void:
	if _set_score.is_valid():
		_set_score.call(p1_score, p2_score)

func _check_win() -> void:
	if p1_score >= winning_score:
		game_over = true
		ball_vel = Vector2.ZERO
		if _set_banner.is_valid():
			_set_banner.call("Player 1 Wins!\nPress R to Restart")
	elif p2_score >= winning_score:
		game_over = true
		ball_vel = Vector2.ZERO
		if _set_banner.is_valid():
			_set_banner.call("Player 2 Wins!\nPress R to Restart")

func reset_match() -> void:
	p1_score = 0
	p2_score = 0
	game_over = false
	_emit_score()
	if _set_banner.is_valid():
		_set_banner.call("")
	reset_round()

func reset_round(direction:int=1) -> void:
	ball_pos = field_size * 0.5
	ball_vel = Vector2(360.0 * direction, randf_range(-240.0, 240.0)) * challenge
	trail.clear()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, field_size), bg_color)
	var dash_h: float = 16.0
	var gap: float = 12.0
	var x: float = field_size.x * 0.5
	var y: float = 0.0
	while y < field_size.y:
		draw_rect(Rect2(Vector2(x - 2.0, y), Vector2(4.0, dash_h)), line_color)
		y += dash_h + gap
	var p1_pos := Vector2(paddle_margin, p1_y - paddle_size.y * 0.5)
	var p2_pos := Vector2(field_size.x - paddle_margin - paddle_size.x, p2_y - paddle_size.y * 0.5)
	draw_rect(Rect2(p1_pos, paddle_size), fg_color)
	draw_rect(Rect2(p2_pos, paddle_size), fg_color)
	var n: int = trail.size()
	for i in range(n):
		var t: float = float(i) / float(max(1, n - 1))
		var a: float = lerp(0.1, 0.6, 1.0 - t)
		draw_circle(trail[i], ball_radius * lerp(0.5, 1.0, 1.0 - t), Color(fg_color, a))
	draw_circle(ball_pos, ball_radius, fg_color)
