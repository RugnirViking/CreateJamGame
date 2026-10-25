extends "res://scripts/quarter_level.gd"

const REQUIRED_KILLS := 8

var enemies: Array[enemytank_tracks] = []
var kills := 0
var captures_complete := false
var kill_label: Label
var player_root: Node3D
var player_body: playertank_tracks


func _enter_tree() -> void:
	set_meta("required_enemy_kills", REQUIRED_KILLS)
	super._enter_tree()


func _ready() -> void:
	super._ready()
	player_root = get_node("playertank")
	player_body = player_root.get_node("vehicle")
	player_body.time_remaining = 300.0
	player_body._update_timer_label()
	for node in find_children("*", "VehicleBody3D", true, false):
		if node is enemytank_tracks:
			enemies.append(node)
			node.defeated.connect(_on_enemy_defeated)
	for marker in get_tree().get_nodes_in_group(&"terrain_target_markers"):
		marker.captured.connect(_on_target_captured)
	kill_label = Label.new()
	kill_label.name = "KillObjective"
	player_root.get_node("AimHUD").add_child(kill_label)
	kill_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	kill_label.offset_top = 40.0
	kill_label.offset_bottom = 72.0
	kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kill_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kill_label.add_theme_font_override("font", preload("res://ussr-stencil/USSR STENCIL/USSR STENCIL WEBFONT.ttf"))
	kill_label.add_theme_font_size_override("font_size", 24)
	kill_label.add_theme_color_override("font_outline_color", Color.BLACK)
	kill_label.add_theme_constant_override("outline_size", 5)
	kill_label.hide()
	_update_objective()


func _on_enemy_defeated() -> void:
	kills += 1
	_update_objective()


func _on_target_captured() -> void:
	for marker in get_tree().get_nodes_in_group(&"terrain_target_markers"):
		if marker.state != terrain_target_marker.State.CAPTURED:
			return
	captures_complete = true
	_update_objective()


func _update_objective() -> void:
	kill_label.text = "KILL %d/%d ENEMIES" % [mini(kills, REQUIRED_KILLS), REQUIRED_KILLS]
	kill_label.visible = captures_complete
	if not captures_complete:
		return
	if kills >= REQUIRED_KILLS:
		player_root.chevron_target = null
		kill_label.hide()
		player_body._win()
	else:
		_point_to_nearest_enemy()


func _process(_delta: float) -> void:
	if captures_complete and kills < REQUIRED_KILLS:
		_point_to_nearest_enemy()


func _point_to_nearest_enemy() -> void:
	var nearest: enemytank_tracks
	var nearest_distance := INF
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.destroyed:
			continue
		var offset := enemy.global_position - player_body.global_position
		var distance := Vector2(offset.x, offset.z).length_squared()
		if distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	player_root.chevron_target = nearest
