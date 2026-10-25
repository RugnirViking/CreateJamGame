extends Control

@export var scroll_speed := 48.0
@export_multiline var credit_text := "ZEROED IN\n\n\nSAM\nProgramming, 3D Modelling, Level Design, Patience\n\n\nSHEMON\nLevel Design, Concept, 3D Modelling, Class\n\n\nSIGNE\nVoice Acting, Cat Design, Style\n\n\nOSCAR\nMusic, Composition, Foley, Swagger\n\n\nTHANK YOU FOR PLAYING"

@onready var roll: Label = $ScrollArea/Roll
@onready var scroll_area: Control = $ScrollArea

var _leaving := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	MenuMusic.play_if_stopped()
	roll.text = credit_text
	roll.position.y = scroll_area.size.y
	$Back.pressed.connect(_back)
	$Back.grab_focus()


func _process(delta: float) -> void:
	roll.position.y -= scroll_speed * delta
	if roll.position.y + roll.size.y < 0.0:
		_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("return_action"):
		get_viewport().set_input_as_handled()
		_back()


func _back() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")
