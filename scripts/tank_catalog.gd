class_name TankCatalog
extends RefCounted

const TANKS := [
	{"name": "GREEN", "type": "TRACKED TANK", "path": "res://scenes/tanks/player/player_tank1.tscn"},
	{"name": "TOG 2", "type": "HEAVY TRACKED TANK", "path": "res://scenes/tanks/player/player_tog2.tscn"},
	{"name": "SDKFZ", "type": "HALF-TRACK", "path": "res://scenes/tanks/player/player_sdkfz.tscn"},
	{"name": "GREYDOG", "type": "WHEELED ARMORED CAR", "path": "res://scenes/tanks/player/player_greydog.tscn"},
	{"name": "CAT TANK", "type": "FELINE FIREPOWER", "path": "res://scenes/tanks/player/player_cattank.tscn"},
]


static func has_scene(path: String) -> bool:
	for tank in TANKS:
		if tank.path == path:
			return true
	return false


static func read_tank(index: int) -> Dictionary:
	# Instantiate off-tree: scene overrides and script defaults are both resolved,
	# without running the player's cameras, audio, HUD, or physics.
	var scene := load(TANKS[index].path) as PackedScene
	var player := scene.instantiate()
	var vehicle := player.get_node("vehicle") as playertank_tracks
	var aiming := player.get_node("followcam")
	var result := {
		"forward_speed": vehicle.max_forward_speed,
		"reverse_speed": vehicle.max_reverse_speed,
		"engine_power": vehicle.engine_force_value,
		"turret_traverse": aiming.turret_traverse_speed,
		"gun_elevation": aiming.gun_elevation_speed,
		"min_elevation": aiming.min_gun_elevation,
		"max_elevation": aiming.max_gun_elevation,
		"max_hp": vehicle.hits_to_destroy,
		"reload_time": vehicle.reload_duration,
		"preview": vehicle.get_node("Model").duplicate(),
	}
	player.free()
	return result
