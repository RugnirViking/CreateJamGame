extends Node

@export var reveal_distance := 35.0

const PAN_DURATION := 1.0
const ORBIT_DURATION := 1.8
const RETURN_DURATION := 1.0
const RECORD_SCRATCH := preload("res://sound/recordscratch.mp3")
const BOSS_MUSIC := preload("res://sound/Boss_intense level music (better).wav")

var _boss: enemytank_tracks
var _player: playertank_tracks
var _hud: VBoxContainer
var _bar: ProgressBar
var _camera: Camera3D
var _original_camera: Camera3D
var _start_pose: Transform3D
var _elapsed := 0.0
var _introduced := false
var _cinematic := false
var _orbit_angle := 0.0
var _was_paused := false
var _terrain_image: Image
var _music: AudioStreamPlayer
var _music_volume_db := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_boss = get_parent().get_node("KittyDanger")
	_boss.show_world_health_bar = false
	_boss._health_bar.hide()
	_player = get_parent().get_node("playertank/vehicle")
	_player.you_win.get_node("Text/Title").text = "THANK YOU"
	_music = get_parent().get_node("BGMusic")
	_music_volume_db = _music.volume_db
	# The reveal pauses gameplay, but its audio must continue through the pan.
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	_music.finished.connect(_on_music_finished)
	get_parent().get_node("playertank").chevron_target = _boss
	_boss.health_changed.connect(_update_health)
	_boss.defeated.connect(_on_defeated)
	_terrain_image = preload("res://scripts/level_catalog.gd").quarter_image(3)
	_build_hud()
	_camera = Camera3D.new()
	_camera.name = "BossIntroCamera"
	add_child(_camera)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_hud = VBoxContainer.new()
	_hud.name = "BossHealth"
	layer.add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hud.anchor_left = 0.18
	_hud.anchor_right = 0.82
	_hud.offset_top = 24.0
	_hud.add_theme_constant_override("separation", 8)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Label.new()
	title.text = "KITTY DANGER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", preload("res://ussr-stencil/USSR STENCIL/USSR STENCIL WEBFONT.ttf"))
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(title)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size.y = 30.0
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.08, 0.025, 0.04, 0.95)
	background.set_border_width_all(3)
	background.border_color = Color(0.95, 0.8, 0.55)
	_bar.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.8, 0.12, 0.3)
	fill.set_border_width_all(3)
	fill.border_color = background.border_color
	_bar.add_theme_stylebox_override("fill", fill)
	_hud.add_child(_bar)
	_update_health(_boss.hits_to_destroy - _boss.shell_hits, _boss.hits_to_destroy)
	_hud.hide()


func _update_health(remaining: int, maximum: int) -> void:
	_bar.max_value = maximum
	_bar.value = remaining


func _process(delta: float) -> void:
	if _cinematic:
		_elapsed += delta
		_update_cinematic()
		return
	if _player.destroyed or _player.you_win.visible:
		_hud.hide()
		return
	if get_tree().paused or _boss.destroyed:
		return
	if not _introduced:
		var offset := _boss.global_position - _player.global_position
		if Vector2(offset.x, offset.z).length() <= reveal_distance:
			_start_intro()


func _start_intro() -> void:
	_introduced = true
	_hud.show()
	_music.stop()
	_music.stream = RECORD_SCRATCH
	_music.volume_db = -8.0
	_music.play()
	_original_camera = get_viewport().get_camera_3d()
	if not is_instance_valid(_original_camera):
		return
	_start_pose = _original_camera.global_transform
	_camera.global_transform = _start_pose
	_camera.fov = _original_camera.fov
	var direction := _start_pose.origin - _boss.global_position
	_orbit_angle = atan2(direction.z, direction.x)
	_elapsed = 0.0
	_cinematic = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_camera.make_current()
	_player.get_parent().get_node("AimHUD").hide()


func _on_music_finished() -> void:
	if _music.stream != RECORD_SCRATCH or _boss.destroyed or _player.destroyed or _player.you_win.visible:
		return
	_music.stream = BOSS_MUSIC
	_music.volume_db = _music_volume_db
	_music.play()


func _orbit_pose(angle: float) -> Transform3D:
	var focus := _boss.global_position + Vector3.UP * 0.4
	var position := focus + Vector3(cos(angle) * 5.0, 2.8, sin(angle) * 5.0)
	# Keep the introduction above the surrounding dunes throughout the orbit.
	position.y = maxf(position.y, preload("res://scripts/level_catalog.gd").height_at(_terrain_image, Vector2(position.x, position.z)) + 1.5)
	return Transform3D(Basis.looking_at(focus - position), position)


func _update_cinematic() -> void:
	if _elapsed < PAN_DURATION:
		var weight := smoothstep(0.0, PAN_DURATION, _elapsed)
		_camera.global_transform = _start_pose.interpolate_with(_orbit_pose(_orbit_angle), weight)
		_camera.fov = lerpf(_original_camera.fov, 55.0, weight)
	elif _elapsed < PAN_DURATION + ORBIT_DURATION:
		var weight := smoothstep(0.0, ORBIT_DURATION, _elapsed - PAN_DURATION)
		_camera.global_transform = _orbit_pose(_orbit_angle + weight * PI * 0.8)
		_camera.fov = 55.0
	elif _elapsed < PAN_DURATION + ORBIT_DURATION + RETURN_DURATION:
		var weight := smoothstep(0.0, RETURN_DURATION, _elapsed - PAN_DURATION - ORBIT_DURATION)
		_camera.global_transform = _orbit_pose(_orbit_angle + PI * 0.8).interpolate_with(_original_camera.global_transform, weight)
		_camera.fov = lerpf(55.0, _original_camera.fov, weight)
	else:
		_finish_intro()


func _finish_intro() -> void:
	if not _cinematic:
		return
	_cinematic = false
	if is_instance_valid(_original_camera):
		_original_camera.make_current()
	_player.get_parent().get_node("AimHUD").show()
	get_tree().paused = _was_paused


func _on_defeated() -> void:
	_finish_intro()
	# A pending scratch must never start boss music over the victory fanfare.
	if _music.stream == RECORD_SCRATCH:
		_music.stop()
		_music.volume_db = _music_volume_db
	_hud.hide()
	_player.get_parent().chevron_target = null
	_player._win()


func _exit_tree() -> void:
	# Leaving the mission mid-introduction must not pause the next menu or level.
	if _cinematic:
		get_tree().paused = _was_paused
