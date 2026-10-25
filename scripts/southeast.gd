extends "res://scripts/quarter_level.gd"


func _enter_tree() -> void:
	set_meta("boss_mission", true)
	super._enter_tree()


func _ready() -> void:
	super._ready()
	var player_body := get_node("playertank/vehicle") as playertank_tracks
	player_body.time_remaining = 300.0
	player_body._update_timer_label()
	var encounter := Node.new()
	encounter.name = "BossEncounter"
	encounter.set_script(preload("res://scripts/boss_encounter.gd"))
	add_child(encounter)
