@tool
extends MeshInstance3D

@export var imageCompressed: Texture2D
@export var height_min: float = 0.0
@export var height_max: float = 20.0

# Click this in the Inspector after changing the settings.
@export_tool_button("Rebuild terrain")
var rebuild_button: Callable:
	get:
		return rebuild

func _ready() -> void:
	rebuild()

func rebuild() -> void:
	if not is_inside_tree() or imageCompressed == null:
		return

	var collision_shape := get_node_or_null(
		"../heightmapCollision"
	) as CollisionShape3D
	if collision_shape == null:
		return

	var image := imageCompressed.get_image()
	if image == null:
		return
	if image.is_compressed():
		if image.decompress() != OK:
			return

	# HeightMapShape3D requires RF, RH, or R8.
	image.convert(Image.FORMAT_RF)

	var shape := HeightMapShape3D.new()
	shape.update_map_data_from_image(image, height_min, height_max)
	collision_shape.shape = shape

	# Build the visible mesh using the collision's height values.
	var width := shape.map_width
	var depth := shape.map_depth
	if width < 2 or depth < 2:
		return

	var heights := shape.map_data
	var offset := Vector2(width - 1, depth - 1) * 0.5
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)

	for z in range(depth):
		for x in range(width):
			surface.set_uv(Vector2(
				float(x) / (width - 1),
				float(z) / (depth - 1)
			))
			surface.add_vertex(Vector3(
				x - offset.x,
				heights[z * width + x],
				z - offset.y
			))

	for z in range(depth - 1):
		for x in range(width - 1):
			var a := z * width + x
			var b := a + 1
			var c := a + width
			var d := c + 1

			# Two triangles per grid square.
			for index in [a, b, c, b, d, c]:
				surface.add_index(index)

	surface.generate_normals()
	mesh = surface.commit()
