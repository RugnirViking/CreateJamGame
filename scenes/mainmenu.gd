extends Control

@export var duration: float = 2.0 
@export var title_rise: float = 150.0
@export var title_rise_duration: float = 0.8
@export var button_fade_duration: float = 0.45
@onready var titleLabel : Label = $Title
@onready var crosshair : TextureRect = $CrosshairNobg
@onready var boom_sound: AudioStreamPlayer = $AudioStreamPlayer
@onready var title_theme: AudioStreamPlayer = $titlemusic
@onready var menu_buttons: VBoxContainer = $MenuButtons
@onready var controls_dialog: AcceptDialog = $ControlsDialog


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	titleLabel.visible_characters = 0
	crosshair.visible = false
	for button: Button in menu_buttons.get_children():
		button.modulate.a = 0.0
		button.disabled = true
	$MenuButtons/Play.pressed.connect(_on_play_pressed)
	$MenuButtons/Controls.pressed.connect(controls_dialog.popup_centered)
	$MenuButtons/Quit.pressed.connect(get_tree().quit)
	if get_tree().get_meta("skip_menu_intro", false):
		get_tree().remove_meta("skip_menu_intro")
		titleLabel.visible_characters = -1
		crosshair.visible = true
		titleLabel.position.y -= title_rise
		crosshair.position.y -= title_rise
		for button: Button in menu_buttons.get_children():
			button.modulate.a = 1.0
			button.disabled = false
		$MenuButtons/Play.grab_focus()
		title_theme.play()
		return
	# Let each boom finish while later letters play their own sound.
	boom_sound.max_polyphony = titleLabel.get_total_character_count() + 1
	
	# Create a tween to animate visible_characters up to the total character count
	var tween = create_tween()
	tween.tween_method(
		_reveal_characters,
		0,
		titleLabel.get_total_character_count(), 
		duration
	)
	await tween.finished
	await get_tree().create_timer(0.5).timeout
	crosshair.visible = true
	boom_sound.play()
	title_theme.play()
	await _show_menu()


func _show_menu() -> void:
	var rise_tween := create_tween().set_parallel(true)
	rise_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	rise_tween.tween_property(titleLabel, "position:y", titleLabel.position.y - title_rise, title_rise_duration)
	rise_tween.tween_property(crosshair, "position:y", crosshair.position.y - title_rise, title_rise_duration)
	await rise_tween.finished

	var fade_tween := create_tween()
	for button: Button in menu_buttons.get_children():
		fade_tween.tween_property(button, "modulate:a", 1.0, button_fade_duration)
	await fade_tween.finished
	for button: Button in menu_buttons.get_children():
		button.disabled = false
	$MenuButtons/Play.grab_focus()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _reveal_characters(character_count: int) -> void:
	for character_index in range(titleLabel.visible_characters, character_count):
		if not titleLabel.text[character_index].strip_edges().is_empty():
			boom_sound.play()
	titleLabel.visible_characters = character_count
