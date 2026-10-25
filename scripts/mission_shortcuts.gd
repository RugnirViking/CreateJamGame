extends Node

signal completion_reset

const Levels = preload("res://scripts/level_catalog.gd")


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if not event.ctrl_pressed or not event.shift_pressed:
		return
	if event.physical_keycode != KEY_F9 and event.keycode != KEY_F9:
		return
	get_viewport().set_input_as_handled()
	var error := Levels.reset_completion()
	if error != OK:
		push_warning("Could not reset mission completion: %s" % error_string(error))
		return
	completion_reset.emit()
