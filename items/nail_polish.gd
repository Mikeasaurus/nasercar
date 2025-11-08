extends Area2D

var _released: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func _on_body_entered(body: Node2D) -> void:
	# Check if nail polish just released
	# (under the car that released it)
	# so we don't gunk up our own car.
	if not _released:
		_released = true
		return
	if "entered_nailpolish" in body:
		body.entered_nailpolish (self, global_position, $CollisionShape2D.shape.radius*scale.x, Color.hex(0x4a2133ff))

func _on_body_exited(body: Node2D) -> void:
	if "exited_nailpolish" in body:
		body.exited_nailpolish(self)
