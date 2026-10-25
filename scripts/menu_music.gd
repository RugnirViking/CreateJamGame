extends AudioStreamPlayer


func _ready() -> void:
	stream = preload("res://sound/Zero In Title Theme.mp3")
	volume_db = 0.0


func play_if_stopped() -> void:
	# Keep the same playback alive while either menu scene is replaced.
	if not playing:
		play()
