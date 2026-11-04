@tool
class_name PuzzlePiece
extends Node3D
## A locally editable tile. The two materials are unique to each scene instance.
@export_range(0, 8) var tile_id: int = 0:
	set(value):
		tile_id = value
		if is_node_ready():
			_set_face()

@onready var side_material: StandardMaterial3D = $Body.material_override
@onready var face_material: StandardMaterial3D = $Face.material_override

func _ready() -> void:
	_set_face()

func _set_face() -> void:
	face_material.uv1_offset = Vector3(float(tile_id % 3) / 3.0, float(tile_id / 3) / 3.0, 0.0)

func set_lifted(value: bool) -> void:
	side_material.albedo_color = Color("efbd59") if value else Color("eee4cb")
