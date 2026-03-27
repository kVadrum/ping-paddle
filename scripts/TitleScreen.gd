## TitleScreen.gd — Splash screen overlay
##
## Displays the game title, a credit line, and a pulsing "press any key"
## prompt. Dismisses itself on any key press or mouse click, emitting
## the start_game signal so Main.gd can unpause the game loop.
##
## This node uses PROCESS_MODE_ALWAYS so the pulse animation runs
## even while the scene tree is paused.

extends CanvasLayer

## Emitted when the player dismisses the title screen.
signal start_game

## Guard against double-fire if key and click arrive on the same frame.
var _dismissed := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Start the "click to play" label invisible, then pulse it
	$VBox/ClickLabel.modulate.a = 0.0
	_fade_click_label()

func _fade_click_label() -> void:
	## Creates an infinite looping tween that pulses the click label's
	## opacity between 30% and 100%, creating a gentle breathing effect.
	var tween := create_tween().set_loops()
	tween.tween_property($VBox/ClickLabel, "modulate:a", 1.0, 0.8)
	tween.tween_property($VBox/ClickLabel, "modulate:a", 0.3, 0.8)

func _unhandled_input(event: InputEvent) -> void:
	# Any key press or mouse click dismisses the title screen
	if event is InputEventKey and event.pressed and not event.echo:
		_go()
	elif event is InputEventMouseButton and event.pressed:
		_go()

func _go() -> void:
	if _dismissed:
		return
	_dismissed = true
	start_game.emit()
	queue_free()
