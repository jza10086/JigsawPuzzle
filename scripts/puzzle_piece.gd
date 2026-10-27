class_name PuzzlePiece
extends Node2D
var artwork: Texture2D
var tile_id := 0
var side := 100.0
var gap := 5.0
var lifted := false

func _draw() -> void:
	var edge := side - gap
	var rect := Rect2(Vector2.ONE * -edge * 0.5, Vector2.ONE * edge)
	if lifted:
		draw_rect(rect.grow(5), Color(0.09, 0.23, 0.2, 0.17))
		draw_rect(Rect2(rect.position + Vector2(2, 9), rect.size), Color(0.07, 0.19, 0.16, 0.22))
		draw_rect(rect.grow(3), Color("f8ca68"))
	if artwork:
		var source_side := float(artwork.get_width()) / 3.0
		var source := Rect2(Vector2(tile_id % 3, tile_id / 3) * source_side, Vector2.ONE * source_side)
		draw_texture_rect_region(artwork, rect, source)
	if gap > 0:
		draw_rect(rect, Color(1, 1, 1, 0.22), false, 1.0)

func set_lifted(value: bool) -> void:
	lifted = value
	z_index = 20 if value else 0
	queue_redraw()
