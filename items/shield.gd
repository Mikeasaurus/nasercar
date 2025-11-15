extends Node2D

class_name Shield

@export var current_rotation: float

func _ready() -> void:
	# Dynamically add the shield elements, so they're registered with the MultiplayerSynchronizer
	# (so they can be properly despawned on clients after an inpact).
	#for i in range(6):
	#	var beat: Beat = load("res://items/beat.tscn").instantiate()
	#	$Beats.add_child(beat)
	#	beat.position = 150 * Vector2.from_angle(PI/3*i)
	# Fade in the shield
	modulate = Color.hex(0xffffff00)
	var tween: Tween = create_tween()
	tween.tween_property(self,"modulate",Color.WHITE,0.2)
	await tween.finished

func _process(_delta: float) -> void:
	global_rotation_degrees = current_rotation

# Clean up after all beats have been used.
func _on_beats_child_exiting_tree(_node: Node) -> void:
	var n: int = len($Beats.get_children())
	if n == 1: queue_free()
