extends Control

@export var duration: float = 2.0 
@onready var titleLabel : Label = $Title
@onready var crosshair : TextureRect = $CrosshairNobg
@onready var boom_sound: AudioStreamPlayer = $AudioStreamPlayer
@onready var title_theme: AudioStreamPlayer = $titlemusic


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	titleLabel.visible_characters = 0
	crosshair.visible = false
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
	await get_tree().create_timer(2.5).timeout
	crosshair.visible = true
	boom_sound.play()
	title_theme.play()


func _reveal_characters(character_count: int) -> void:
	for character_index in range(titleLabel.visible_characters, character_count):
		if not titleLabel.text[character_index].strip_edges().is_empty():
			boom_sound.play()
	titleLabel.visible_characters = character_count
