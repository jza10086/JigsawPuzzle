class_name PuzzlePiece
extends Node3D
## A solid tile with one ninth of the shared illustration on its upper face.

var artwork: Texture2D
var tile_id: int = 0
var side_material: StandardMaterial3D

func _ready() -> void:
	side_material = StandardMaterial3D.new()
	side_material.albedo_color = Color("eee4cb")
	side_material.roughness = 0.72
	var body: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.96, 0.20, 1.96)
	body.mesh = box
	body.material_override = side_material
	add_child(body)

	var face: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(1.96, 1.96)
	face.mesh = plane
	face.position.y = 0.101
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = artwork
	material.uv1_scale = Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0)
	material.uv1_offset = Vector3(float(tile_id % 3) / 3.0, float(tile_id / 3) / 3.0, 0.0)
	material.roughness = 0.9
	face.material_override = material
	add_child(face)

func set_lifted(value: bool) -> void:
	side_material.albedo_color = Color("efbd59") if value else Color("eee4cb")
