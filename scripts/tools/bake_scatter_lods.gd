extends SceneTree

# Run with Godot --headless --path . --script res://scripts/tools/bake_scatter_lods.gd
# Bake ordinary ArrayMeshes so mesh simplification is never needed in an exported game.
const OUTPUT := "res://art/models/scatter_lod_meshes.res"


func _initialize() -> void:
	var meshes: Dictionary = {}
	var directory := DirAccess.open("res://scenes/scatter")
	for file in directory.get_files():
		if not file.ends_with("_visual.tscn"):
			continue
		var path := "res://scenes/scatter/" + file
		var prototype: Node = load(path).instantiate()
		var parts: Array[Dictionary] = []
		_collect_meshes(prototype, parts)
		for index in parts.size():
			var mesh: Mesh = parts[index]["mesh"]
			var importer := ImporterMesh.new()
			for surface in mesh.get_surface_count():
				var primitive: int = mesh.surface_get_primitive_type(surface) if mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
				importer.add_surface(primitive, mesh.surface_get_arrays(surface), [], {}, mesh.surface_get_material(surface))
			importer.generate_lods(60.0, 25.0, [])
			var baked := importer.get_mesh()
			baked.resource_name = file.get_basename() + "_part_%d_LOD" % index
			meshes[path + "#" + str(index)] = baked
			var levels := 0
			for surface in importer.get_surface_count():
				levels += importer.get_surface_lod_count(surface)
			print(file, " part ", index, " baked LOD levels=", levels)
		prototype.free()
	var library := Resource.new()
	library.set_meta(&"meshes", meshes)
	var result := ResourceSaver.save(library, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	if result != OK:
		push_error("Cannot save scatter LOD library: " + error_string(result))
	print("Scatter LOD library saved: ", OUTPUT, " parts=", meshes.size())
	quit(0 if result == OK else 1)


func _collect_meshes(node: Node, parts: Array[Dictionary]) -> void:
	# Keep the same depth-first part order as scatter_patch.gd. LODs retain the
	# original local vertex coordinates; scatter supplies each part's transform.
	if node is MeshInstance3D and node.mesh != null and node.visible:
		parts.append({"mesh": node.mesh})
	for child in node.get_children():
		_collect_meshes(child, parts)
