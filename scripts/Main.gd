## Main.gd — HUD controller, input routing, theme management, window management
##
## This is the root script. It owns:
##   - The HUD layer (score, win banner, bottom bar controls)
##   - Theme switching (dark/light) and styling of all UI elements
##   - Window controls (minimize, fullscreen/windowed toggle, exit)
##   - Title screen lifecycle
##   - Routing slider/toggle values down to Game.gd
##
## Game.gd owns gameplay; this script owns everything around it.

extends Node

# ─── Layout Constants ────────────────────────────────────────────────────────
const BOTTOM_BAR_HEIGHT := 40.0  ## Height reserved for the controls bar

# ─── Node References ─────────────────────────────────────────────────────────
@onready var game            := $Game
@onready var hud             := $HUD
@onready var score_label     := $HUD/ScoreLabel
@onready var win_banner      := $HUD/WinBanner
@onready var banner_label    := $HUD/WinBanner/BannerLabel

@onready var theme_btn       := $HUD/TopRight/ThemeButton
@onready var min_btn         := $HUD/TopRight/WindowGroup/MinButton
@onready var win_toggle_btn  := $HUD/TopRight/WindowGroup/WinToggleButton
@onready var exit_btn        := $HUD/TopRight/WindowGroup/ExitButton

@onready var keys_label      := $HUD/BottomBar/MarginContainer/HBox/KeysLabel
@onready var speed_label     := $HUD/BottomBar/MarginContainer/HBox/SpeedLabel
@onready var paddle_label    := $HUD/BottomBar/MarginContainer/HBox/PaddleLabel
@onready var ai_diff_label   := $HUD/BottomBar/MarginContainer/HBox/AIDiffLabel

@onready var slider          := $HUD/BottomBar/MarginContainer/HBox/ChallengeSlider
@onready var paddle_slider   := $HUD/BottomBar/MarginContainer/HBox/PaddleSlider
@onready var ai_toggle       := $HUD/BottomBar/MarginContainer/HBox/AIToggle
@onready var ai_diff         := $HUD/BottomBar/MarginContainer/HBox/AIDiffSlider
@onready var bottom_bar      := $HUD/BottomBar

# ─── State ───────────────────────────────────────────────────────────────────
var dark_mode := true
var title_screen_scene := preload("res://scenes/TitleScreen.tscn")

## Tracks why the game is paused so we don't accidentally unpause
## when a different pause reason is still active.
enum PauseReason { NONE, USER, MINIMIZED, TITLE_SCREEN }
var _pause_reason := PauseReason.NONE


# ══════════════════════════════════════════════════════════════════════════════
#  INITIALIZATION
# ══════════════════════════════════════════════════════════════════════════════

func _enter_tree() -> void:
	# PROCESS_MODE_ALWAYS ensures we can handle input even when paused
	# (needed for unpause key, window controls, title screen dismiss).
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	# Start fullscreen if not already
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	# Enforce minimum window size to prevent layout collapse
	DisplayServer.window_set_min_size(Vector2i(800, 500))

	# HUD and banner must respond during pause (for buttons, win text)
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	$HUD/TopRight.process_mode = Node.PROCESS_MODE_ALWAYS
	win_banner.process_mode = Node.PROCESS_MODE_ALWAYS

	# Score label styling
	score_label.add_theme_font_size_override("font_size", 96)
	score_label.add_theme_constant_override("outline_size", 2)

	# Win banner styling
	banner_label.add_theme_font_size_override("font_size", 48)

	# Connect Game signals
	game.score_changed.connect(_update_score)
	game.banner_changed.connect(_set_banner)
	game.call_deferred("set_bottom_margin", BOTTOM_BAR_HEIGHT)

	# Show title screen on startup
	_show_title_screen()

	# Connect bottom bar controls
	slider.value_changed.connect(_on_challenge_changed)
	paddle_slider.value_changed.connect(_on_paddle_changed)
	ai_toggle.toggled.connect(_on_ai_toggled)
	ai_diff.value_changed.connect(_on_ai_diff_changed)

	# Connect top-right buttons
	theme_btn.pressed.connect(_on_theme_pressed)
	min_btn.pressed.connect(_on_minimize)
	win_toggle_btn.pressed.connect(_on_win_toggle)
	exit_btn.pressed.connect(_on_exit_pressed)

	# Prevent buttons from holding focus after click (avoids "stuck" highlight)
	for btn in [theme_btn, min_btn, win_toggle_btn, exit_btn]:
		btn.focus_mode = Control.FOCUS_NONE

	# Push initial slider values to Game
	_on_challenge_changed(slider.value)
	_on_paddle_changed(paddle_slider.value)
	_on_ai_toggled(ai_toggle.button_pressed)
	_on_ai_diff_changed(ai_diff.value)

	# Apply the initial theme and window button labels
	_apply_theme()
	_update_win_toggle_label()

	# Track viewport resize for window toggle label updates
	get_viewport().size_changed.connect(_on_viewport_resized)


# ══════════════════════════════════════════════════════════════════════════════
#  PAUSE MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════
## Instead of toggling `get_tree().paused` directly from multiple places,
## we track the reason so competing pause sources don't clobber each other.
## For example, if the title screen is showing, a focus-in event shouldn't
## unpause the game.

func _pause(reason: PauseReason) -> void:
	_pause_reason = reason
	get_tree().paused = true

func _unpause(reason: PauseReason) -> void:
	## Only unpauses if the given reason matches the current pause reason.
	## Prevents e.g. focus-in from unpausing during the title screen.
	if _pause_reason == reason:
		_pause_reason = PauseReason.NONE
		get_tree().paused = false


# ══════════════════════════════════════════════════════════════════════════════
#  TITLE SCREEN
# ══════════════════════════════════════════════════════════════════════════════

func _show_title_screen() -> void:
	## Instantiates and styles the title screen overlay, pausing the game
	## until the player dismisses it with any key or click.
	_pause(PauseReason.TITLE_SCREEN)

	var title := title_screen_scene.instantiate()

	# Style to match current theme
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
	_unpause(PauseReason.TITLE_SCREEN)


# ══════════════════════════════════════════════════════════════════════════════
#  WINDOW MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════

func _is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func _update_win_toggle_label() -> void:
	## Updates the window toggle button icon: □ when fullscreen, ■ when windowed.
	if _is_fullscreen():
		win_toggle_btn.text = "\u25a1"
		win_toggle_btn.tooltip_text = "Windowed"
	else:
		win_toggle_btn.text = "\u25a0"
		win_toggle_btn.tooltip_text = "Fullscreen"

func _on_minimize() -> void:
	_pause(PauseReason.MINIMIZED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)

func _on_win_toggle() -> void:
	## Toggles between fullscreen and a centered 1280×720 window.
	if _is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		# Center the window on screen
		var screen_size := DisplayServer.screen_get_size()
		var win_size := DisplayServer.window_get_size()
		DisplayServer.window_set_position(Vector2i(
			(screen_size.x - win_size.x) / 2,
			(screen_size.y - win_size.y) / 2
		))
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	# Deferred because the mode change triggers a resize before it's fully applied
	call_deferred("_update_win_toggle_label")

func _on_exit_pressed() -> void:
	get_tree().quit()

func _on_viewport_resized() -> void:
	call_deferred("_update_win_toggle_label")
	game.handle_resized()


# ══════════════════════════════════════════════════════════════════════════════
#  SYSTEM NOTIFICATIONS
# ══════════════════════════════════════════════════════════════════════════════

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		# Only unpause if we were paused because of a minimize.
		# This prevents unpausing during title screen or user-initiated pause.
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED:
			_unpause(PauseReason.MINIMIZED)


# ══════════════════════════════════════════════════════════════════════════════
#  KEYBOARD INPUT
# ══════════════════════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_P:
				_pause(PauseReason.USER)
			KEY_G:
				_unpause(PauseReason.USER)
			KEY_R:
				game.reset_match()
			KEY_T:
				dark_mode = not dark_mode
				_apply_theme()
			KEY_ESCAPE:
				get_tree().quit()


# ══════════════════════════════════════════════════════════════════════════════
#  GAME STATE CALLBACKS
# ══════════════════════════════════════════════════════════════════════════════

func _update_score(p1: int, p2: int) -> void:
	score_label.text = "%d : %d" % [p1, p2]

func _set_banner(text: String) -> void:
	win_banner.visible = text.length() > 0
	banner_label.text = text


# ══════════════════════════════════════════════════════════════════════════════
#  BOTTOM BAR CONTROL HANDLERS
# ══════════════════════════════════════════════════════════════════════════════

func _on_challenge_changed(v: float) -> void:
	game.set_challenge(v)

func _on_paddle_changed(v: float) -> void:
	game.set_paddle_scale(v)

func _on_ai_toggled(on: bool) -> void:
	game.set_ai_enabled(on)

func _on_ai_diff_changed(v: float) -> void:
	game.set_ai_difficulty(v)

func _on_theme_pressed() -> void:
	dark_mode = not dark_mode
	_apply_theme()


# ══════════════════════════════════════════════════════════════════════════════
#  THEME ENGINE
# ══════════════════════════════════════════════════════════════════════════════

func _apply_theme() -> void:
	## Applies the current dark/light theme to every UI element.
	## Game.gd handles its own field colors via set_dark_mode().
	game.set_dark_mode(dark_mode)

	var fg := Color(0.95, 0.95, 0.95) if dark_mode else Color(0.12, 0.12, 0.12)
	var outline := Color(0, 0, 0, 0.75) if dark_mode else Color(1, 1, 1, 0.75)

	# Theme toggle icon — crescent moon for dark, sun for light
	theme_btn.text = "\u263d" if dark_mode else "\u2600"

	# Style all top-right buttons
	_style_all_buttons(fg)

	# Score display
	score_label.add_theme_color_override("font_color", fg)
	score_label.add_theme_color_override("font_outline_color", outline)

	# Win banner overlay — semi-transparent to dim the field behind it
	var overlay_color := Color(0, 0, 0, 0.6) if dark_mode \
		else Color(1, 1, 1, 0.6)
	win_banner.color = overlay_color
	banner_label.add_theme_color_override("font_color", fg)

	# Bottom bar background
	var bar_bg := Color(0.15, 0.15, 0.15) if dark_mode \
		else Color(0.88, 0.88, 0.88)
	var style := StyleBoxFlat.new()
	style.bg_color = bar_bg
	style.content_margin_left   = 8.0
	style.content_margin_right  = 8.0
	style.content_margin_top    = 6.0
	style.content_margin_bottom = 6.0
	bottom_bar.add_theme_stylebox_override("panel", style)

	# Bottom bar labels — all match the foreground color
	for label in [keys_label, speed_label, paddle_label, ai_diff_label]:
		label.add_theme_color_override("font_color", fg)

	# AI checkbox — lock all color states so hover doesn't change text color
	for color_name in ["font_color", "font_hover_color",
			"font_pressed_color", "font_focus_color"]:
		ai_toggle.add_theme_color_override(color_name, fg)


# ══════════════════════════════════════════════════════════════════════════════
#  BUTTON STYLING
# ══════════════════════════════════════════════════════════════════════════════
## Buttons use custom StyleBoxFlat overrides for a minimal, clean look.
## The window buttons (min/toggle/exit) are styled as a connected group
## with shared borders, matching the look of native Linux title bar buttons.

func _make_btn_style(bg_alpha: float, border_alpha: float, fg: Color,
		r_tl := 3, r_tr := 3, r_bl := 3, r_br := 3,
		bw_l := 1, bw_r := 1, bw_t := 1, bw_b := 1) -> StyleBoxFlat:
	## Creates a StyleBoxFlat for button states with configurable corner radii
	## and border widths. Used to build the connected button group effect.
	var s := StyleBoxFlat.new()
	s.bg_color     = Color(fg, bg_alpha)
	s.border_color = Color(fg, border_alpha)
	s.border_width_left   = bw_l
	s.border_width_right  = bw_r
	s.border_width_top    = bw_t
	s.border_width_bottom = bw_b
	s.corner_radius_top_left     = r_tl
	s.corner_radius_top_right    = r_tr
	s.corner_radius_bottom_left  = r_bl
	s.corner_radius_bottom_right = r_br
	s.content_margin_left   = 6.0
	s.content_margin_right  = 6.0
	s.content_margin_top    = 2.0
	s.content_margin_bottom = 2.0
	return s

func _style_btn(btn: Button, normal: StyleBoxFlat, hovered: StyleBoxFlat,
		fg: Color) -> void:
	## Applies consistent styling to a button: normal/hover/pressed/focus states,
	## font size, and foreground color.
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hovered)
	btn.add_theme_stylebox_override("pressed", normal)  # No "stuck" pressed look
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_size_override("font_size", 12)
	for color_name in ["font_color", "font_hover_color",
			"font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(color_name, fg)

func _style_all_buttons(fg: Color) -> void:
	## Styles all top-right buttons with the current theme color.
	## The theme button stands alone; window buttons form a connected group.
	var na := 0.12  # Normal background alpha
	var nb := 0.18  # Normal border alpha
	var ha := 0.25  # Hover background alpha
	var hb := 0.35  # Hover border alpha

	# Theme button — standalone, fully rounded corners
	var t_n := _make_btn_style(na, nb, fg)
	var t_h := _make_btn_style(ha, hb, fg)
	_style_btn(theme_btn, t_n, t_h, fg)
	theme_btn.add_theme_font_size_override("font_size", 16)

	# Window group: [min | toggle | exit] — connected borders
	# Left button: rounded left corners, flat right edge
	var gl_n := _make_btn_style(na, nb, fg, 3, 0, 3, 0, 1, 0, 1, 1)
	var gl_h := _make_btn_style(ha, hb, fg, 3, 0, 3, 0, 1, 0, 1, 1)
	_style_btn(min_btn, gl_n, gl_h, fg)
	min_btn.text = "\u2014"  # Em dash — for minimize

	# Middle button: no rounded corners, no left/right borders
	var gm_n := _make_btn_style(na, nb, fg, 0, 0, 0, 0, 0, 0, 1, 1)
	var gm_h := _make_btn_style(ha, hb, fg, 0, 0, 0, 0, 0, 0, 1, 1)
	_style_btn(win_toggle_btn, gm_n, gm_h, fg)

	# Right button: rounded right corners, flat left edge
	var gr_n := _make_btn_style(na, nb, fg, 0, 3, 0, 3, 0, 1, 1, 1)
	var gr_h := _make_btn_style(ha, hb, fg, 0, 3, 0, 3, 0, 1, 1, 1)
	_style_btn(exit_btn, gr_n, gr_h, fg)
