extends Node2D

class_name Shield

@export var current_rotation: float

func _ready() -> void:
	# Fade in the shield
	modulate = Color.hex(0xffffff00)
	var tween: Tween = create_tween()
	tween.tween_property(self,"modulate",Color.WHITE,0.2)
	await tween.finished

func _physics_process(_delta: float) -> void:
	global_rotation_degrees = current_rotation

# Clean up after all beats have been used.
func _on_beats_child_exiting_tree(_node: Node) -> void:
	var n: int = len($Beats.get_children())
	if n == 1 and multiplayer.get_unique_id() == 1:
		queue_free()
