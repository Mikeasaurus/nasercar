extends AnimatableBody2D

func _on_front_body_entered(body: Node2D) -> void:
	if multiplayer.get_unique_id() != 1: return
	# Honk cars that get too close.
	if body is Car and not $Front/Horn.playing:
		$Front/Horn.play()
