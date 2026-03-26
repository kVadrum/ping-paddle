extends Node

const BOTTOM_BAR_HEIGHT := 56.0

@onready var game := $Game
@onready var hud := $HUD
@onready var score_label := $HUD/ScoreLabel
@onready var exit_btn := $HUD/ExitButton
@onready var win_banner := $HUD/WinBanner
@onready var banner_label := $HUD/WinBanner/BannerLabel

@onready var slider := $HUD/BottomBar/ChallengeSlider
@onready var paddle_slider := $HUD/BottomBar/PaddleSlider
@onready var ai_toggle := $HUD/BottomBar/AIToggle
@onready var ai_diff := $HUD/BottomBar/AIDiffSlider

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	exit_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	win_banner.process_mode = Node.PROCESS_MODE_ALWAYS

	score_label.add_theme_font_size_override("font_size", 96)
	score_label.add_theme_constant_override("outline_size", 2)
	score_label.add_theme_color_override("font_outline_color", Color(0,0,0,0.75))

	_update_score(0, 0)
	game.call_deferred("set_score_callback", Callable(self, "_update_score"))
	game.call_deferred("set_banner_callback", Callable(self, "_set_banner"))
	game.call_deferred("set_bottom_margin", BOTTOM_BAR_HEIGHT)

	slider.value_changed.connect(_on_challenge_changed)
	paddle_slider.value_changed.connect(_on_paddle_changed)
	ai_toggle.toggled.connect(_on_ai_toggled)
	ai_diff.value_changed.connect(_on_ai_diff_changed)
	exit_btn.pressed.connect(_on_exit_pressed)

	_on_challenge_changed(slider.value)
	_on_paddle_changed(paddle_slider.value)
	_on_ai_toggled(ai_toggle.button_pressed)
	_on_ai_diff_changed(ai_diff.value)

	get_viewport().size_changed.connect(_on_viewport_resized)

func _on_exit_pressed() -> void:
	get_tree().quit()

func _set_banner(text: String) -> void:
	var show := text.length() > 0
	win_banner.visible = show
	banner_label.text = text

func _on_viewport_resized() -> void:
	if game.has_method("handle_resized"):
		game.handle_resized()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			get_tree().paused = true
		elif event.keycode == KEY_C:
			get_tree().paused = false
		elif event.keycode == KEY_R:
			if game.has_method("reset_match"):
				game.reset_match() # full reset works even when paused

func _update_score(p1:int, p2:int) -> void:
	score_label.text = "%d : %d" % [p1, p2]

func _on_challenge_changed(v: float) -> void:
	if game.has_method("set_challenge"):
		game.set_challenge(v)

func _on_paddle_changed(v: float) -> void:
	if game.has_method("set_paddle_scale"):
		game.set_paddle_scale(v)

func _on_ai_toggled(on: bool) -> void:
	if game.has_method("set_ai_enabled"):
		game.set_ai_enabled(on)

func _on_ai_diff_changed(v: float) -> void:
	if game.has_method("set_ai_difficulty"):
		game.set_ai_difficulty(v)
