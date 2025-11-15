extends Node2D

class_name BeatBlast

# Pick a phrase to write.
func _ready() -> void:
	if multiplayer.get_unique_id() != 1: return
	var rating: int = randi_range(1,5)
	if rating == 5:
		$Label.text = "Perfect!"

# Keep the effect oriented at a consistent angle.
func _process(_delta: float) -> void:
	global_rotation = 0

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	queue_free()
