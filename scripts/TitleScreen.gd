extends CanvasLayer

signal start_game

var _dismissed := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$VBox/ClickLabel.modulate.a = 0.0
	_fade_click_label()

func _fade_click_label() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property($VBox/ClickLabel, "modulate:a", 1.0, 0.8)
	tween.tween_property($VBox/ClickLabel, "modulate:a", 0.3, 0.8)

func _unhandled_input(event: InputEvent) -> void:
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
