extends Control

@export var line_color := Color(0.75, 0.94, 0.79, 0.95)
@onready var minimap: ColorRect = $"../ColorRect"
var turret_yaw := 0.0
var gun_pitch := 0.0
var _panel := StyleBoxFlat.new()


func _ready() -> void:
	_panel.bg_color = minimap.color # Color(0.025, 0.045, 0.035, 0.78)
	_panel.set_corner_radius_all(4)


func update_aim(yaw: float, pitch: float) -> void:
	turret_yaw = yaw
	gun_pitch = pitch
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var half_box := Vector2(minf(size.x * 0.2, 240.0), minf(size.y * 0.23, 150.0))
	# Open corner marks leave the target clear inside the scope.
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			var corner := center + half_box * Vector2(x, y)
			draw_line(corner, corner - Vector2(x * 22.0, 0.0), line_color, 1.0, true)
			draw_line(corner, corner - Vector2(0.0, y * 22.0), line_color, 1.0, true)
	var panel := Vector2(28.0, size.y - 224.0)
	draw_style_box(_panel, Rect2(panel, Vector2(188.0, 196.0)))
	var diagram := panel + Vector2(94.0, 91.0)
	draw_rect(Rect2(diagram - Vector2(28.0, 42.0), Vector2(56.0, 84.0)), line_color, false, 1.5)
	draw_line(diagram + Vector2(-19.0, -47.0), diagram + Vector2(19.0, -47.0), line_color, 2.0, true)
	draw_circle(diagram, 19.0, line_color, false, 1.5, true)
	# The hull stays upright; positive Godot yaw turns left on this top view.
	draw_set_transform(diagram, -turret_yaw)
	draw_rect(Rect2(-3.0, -57.0, 6.0, 39.0), line_color, false, 1.5)
	draw_set_transform(Vector2.ZERO)
	var font := get_theme_default_font()
	draw_string(font, panel + Vector2(16.0, 180.0), "SCROLL OUT / ESC", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, line_color * Color(1.0, 1.0, 1.0, 0.65))
