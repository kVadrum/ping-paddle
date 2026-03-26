extends Node

const BOTTOM_BAR_HEIGHT := 40.0

@onready var game := $Game
@onready var hud := $HUD
@onready var score_label := $HUD/ScoreLabel
@onready var win_banner := $HUD/WinBanner
@onready var banner_label := $HUD/WinBanner/BannerLabel

@onready var theme_btn := $HUD/TopRight/ThemeButton
@onready var min_btn := $HUD/TopRight/WindowGroup/MinButton
@onready var win_toggle_btn := $HUD/TopRight/WindowGroup/WinToggleButton
@onready var exit_btn := $HUD/TopRight/WindowGroup/ExitButton
@onready var keys_label := $HUD/BottomBar/MarginContainer/HBox/KeysLabel
@onready var speed_label := $HUD/BottomBar/MarginContainer/HBox/SpeedLabel
@onready var paddle_label := $HUD/BottomBar/MarginContainer/HBox/PaddleLabel
@onready var ai_diff_label := $HUD/BottomBar/MarginContainer/HBox/AIDiffLabel

@onready var slider := $HUD/BottomBar/MarginContainer/HBox/ChallengeSlider
@onready var paddle_slider := $HUD/BottomBar/MarginContainer/HBox/PaddleSlider
@onready var ai_toggle := $HUD/BottomBar/MarginContainer/HBox/AIToggle
@onready var ai_diff := $HUD/BottomBar/MarginContainer/HBox/AIDiffSlider
@onready var bottom_bar := $HUD/BottomBar

var dark_mode := true
var title_screen_scene := preload("res://scenes/TitleScreen.tscn")

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	$HUD/TopRight.process_mode = Node.PROCESS_MODE_ALWAYS
	win_banner.process_mode = Node.PROCESS_MODE_ALWAYS

	score_label.add_theme_font_size_override("font_size", 96)
	score_label.add_theme_constant_override("outline_size", 2)

	_update_score(0, 0)
	game.call_deferred("set_score_callback", Callable(self, "_update_score"))
	game.call_deferred("set_banner_callback", Callable(self, "_set_banner"))
	game.call_deferred("set_bottom_margin", BOTTOM_BAR_HEIGHT)

	_show_title_screen()

	slider.value_changed.connect(_on_challenge_changed)
	paddle_slider.value_changed.connect(_on_paddle_changed)
	ai_toggle.toggled.connect(_on_ai_toggled)
	ai_diff.value_changed.connect(_on_ai_diff_changed)

	theme_btn.pressed.connect(_on_theme_pressed)
	min_btn.pressed.connect(_on_minimize)
	win_toggle_btn.pressed.connect(_on_win_toggle)
	exit_btn.pressed.connect(_on_exit_pressed)

	# Release focus after any button click so pressed frame doesn't stick
	for btn in [theme_btn, min_btn, win_toggle_btn, exit_btn]:
		btn.focus_mode = Control.FOCUS_NONE

	_on_challenge_changed(slider.value)
	_on_paddle_changed(paddle_slider.value)
	_on_ai_toggled(ai_toggle.button_pressed)
	_on_ai_diff_changed(ai_diff.value)

	_apply_theme()
	_update_win_toggle_label()

	get_viewport().size_changed.connect(_on_viewport_resized)

func _is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func _update_win_toggle_label() -> void:
	if _is_fullscreen():
		win_toggle_btn.text = "\u25a1"
		win_toggle_btn.tooltip_text = "Windowed"
	else:
		win_toggle_btn.text = "\u25a0"
		win_toggle_btn.tooltip_text = "Fullscreen"

func _make_btn_style(bg_alpha: float, border_alpha: float, fg: Color,
		r_tl := 3, r_tr := 3, r_bl := 3, r_br := 3,
		bw_l := 1, bw_r := 1, bw_t := 1, bw_b := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(fg, bg_alpha)
	s.border_color = Color(fg, border_alpha)
	s.border_width_left = bw_l
	s.border_width_right = bw_r
	s.border_width_top = bw_t
	s.border_width_bottom = bw_b
	s.corner_radius_top_left = r_tl
	s.corner_radius_top_right = r_tr
	s.corner_radius_bottom_left = r_bl
	s.corner_radius_bottom_right = r_br
	s.content_margin_left = 6.0
	s.content_margin_right = 6.0
	s.content_margin_top = 2.0
	s.content_margin_bottom = 2.0
	return s

func _style_btn(btn: Button, normal: StyleBoxFlat, hovered: StyleBoxFlat, fg: Color) -> void:
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hovered)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_color_override("font_pressed_color", fg)
	btn.add_theme_color_override("font_focus_color", fg)

func _style_all_buttons(fg: Color) -> void:
	var na := 0.12
	var nb := 0.18
	var ha := 0.25
	var hb := 0.35

	# Theme button — standalone, full rounded
	var t_n := _make_btn_style(na, nb, fg)
	var t_h := _make_btn_style(ha, hb, fg)
	_style_btn(theme_btn, t_n, t_h, fg)
	theme_btn.add_theme_font_size_override("font_size", 16)

	# Window group of 3: [min | toggle | X]
	# Left
	var gl_n := _make_btn_style(na, nb, fg, 3, 0, 3, 0, 1, 0, 1, 1)
	var gl_h := _make_btn_style(ha, hb, fg, 3, 0, 3, 0, 1, 0, 1, 1)
	_style_btn(min_btn, gl_n, gl_h, fg)
	min_btn.text = "\u2014"

	# Middle
	var gm_n := _make_btn_style(na, nb, fg, 0, 0, 0, 0, 0, 0, 1, 1)
	var gm_h := _make_btn_style(ha, hb, fg, 0, 0, 0, 0, 0, 0, 1, 1)
	_style_btn(win_toggle_btn, gm_n, gm_h, fg)

	# Right
	var gr_n := _make_btn_style(na, nb, fg, 0, 3, 0, 3, 0, 1, 1, 1)
	var gr_h := _make_btn_style(ha, hb, fg, 0, 3, 0, 3, 0, 1, 1, 1)
	_style_btn(exit_btn, gr_n, gr_h, fg)

func _show_title_screen() -> void:
	get_tree().paused = true
	var title := title_screen_scene.instantiate()
	# Style title screen labels
	var fg := Color(0.95, 0.95, 0.95) if dark_mode else Color(0.12, 0.12, 0.12)
	var title_label: Label = title.get_node("VBox/Title")
	title_label.add_theme_font_size_override("font_size", 72)
	title_label.add_theme_color_override("font_color", fg)
	var subtitle: Label = title.get_node("VBox/Subtitle")
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(fg, 0.5))
	var click_label: Label = title.get_node("VBox/ClickLabel")
	click_label.add_theme_font_size_override("font_size", 20)
	click_label.add_theme_color_override("font_color", fg)
	var credit: Label = title.get_node("VBox/Credit")
	credit.add_theme_font_size_override("font_size", 14)
	credit.add_theme_color_override("font_color", Color(fg, 0.35))
	title.start_game.connect(_on_title_dismissed)
	add_child(title)

func _on_title_dismissed() -> void:
	get_tree().paused = false

func _on_exit_pressed() -> void:
	get_tree().quit()

func _on_minimize() -> void:
	get_tree().paused = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)

func _on_win_toggle() -> void:
	if _is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		var screen_size := DisplayServer.screen_get_size()
		var win_size := DisplayServer.window_get_size()
		DisplayServer.window_set_position(Vector2i(
			(screen_size.x - win_size.x) / 2,
			(screen_size.y - win_size.y) / 2
		))
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	call_deferred("_update_win_toggle_label")

func _set_banner(text: String) -> void:
	var show := text.length() > 0
	win_banner.visible = show
	banner_label.text = text

func _on_viewport_resized() -> void:
	call_deferred("_update_win_toggle_label")
	if game.has_method("handle_resized"):
		game.handle_resized()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED:
			# Don't auto-unpause if title screen is still showing
			if not _has_title_screen():
				get_tree().paused = false

func _has_title_screen() -> bool:
	for child in get_children():
		if child is CanvasLayer and child.has_signal("start_game"):
			return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			get_tree().paused = true
		elif event.keycode == KEY_G:
			get_tree().paused = false
		elif event.keycode == KEY_R:
			if game.has_method("reset_match"):
				game.reset_match()
		elif event.keycode == KEY_T:
			dark_mode = not dark_mode
			_apply_theme()
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()

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

func _on_theme_pressed() -> void:
	dark_mode = not dark_mode
	_apply_theme()

func _apply_theme() -> void:
	if game.has_method("set_dark_mode"):
		game.set_dark_mode(dark_mode)

	var fg := Color(0.95, 0.95, 0.95) if dark_mode else Color(0.12, 0.12, 0.12)
	var outline := Color(0, 0, 0, 0.75) if dark_mode else Color(1, 1, 1, 0.75)

	# Theme icon — sun/moon text glyph
	theme_btn.text = "\u263d" if dark_mode else "\u2600"

	# Top-right buttons
	_style_all_buttons(fg)

	# Score
	score_label.add_theme_color_override("font_color", fg)
	score_label.add_theme_color_override("font_outline_color", outline)

	# Banner
	banner_label.add_theme_color_override("font_color", fg)

	# Footer bar
	var bar_bg := Color(0.15, 0.15, 0.15) if dark_mode else Color(0.88, 0.88, 0.88)
	var style := StyleBoxFlat.new()
	style.bg_color = bar_bg
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	bottom_bar.add_theme_stylebox_override("panel", style)

	# Footer labels
	for label in [keys_label, speed_label, paddle_label, ai_diff_label]:
		label.add_theme_color_override("font_color", fg)

	# AI checkbox — lock color so it doesn't change on hover
	ai_toggle.add_theme_color_override("font_color", fg)
	ai_toggle.add_theme_color_override("font_hover_color", fg)
	ai_toggle.add_theme_color_override("font_pressed_color", fg)
	ai_toggle.add_theme_color_override("font_focus_color", fg)
