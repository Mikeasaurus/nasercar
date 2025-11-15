extends AnimatedSprite2D

class_name Beat

func _handle_impact(object: Node2D) -> void:
	# Only server / local client controls collisions.
	if multiplayer.get_unique_id() != 1: return
	# Car collision code adapted from beetle scene.
	var dv: Vector2 = Vector2.from_angle(position.angle()+global_rotation+PI/2) * 1000.0
	var quiet: bool = false
	if "_crash_effect" in object:
		if "apply_impulse" in object:
			object.apply_impulse(dv)
		if "apply_torque_impulse" in object:
			object.apply_torque_impulse(20000)
		if "scream" in object:
			object.scream()
		object._crash_effect()
	# Collision with beetle?
	elif "buzz_off" in object:
		# Ignore beetle if it came from our own car.
		if "originator" in object and object.originator == get_parent().get_parent().get_parent():
			return
		if "velocity" in object:
			object.velocity += dv
		object.buzz_off()
	# Collision with beats from another car's shield?
	elif object is Beat or object.get_parent() is Beat:
		quiet = true
	else:
		return
	var beatblast: BeatBlast = load("res://items/beatblast.tscn").instantiate()
	add_sibling(beatblast,true)
	beatblast.position = position
	if quiet: beatblast.get_node("Label").text = ""
	_queue_free.rpc()  # MultiplayerSpawner can't handle this automatically for some reason?

func _on_area_2d_body_entered(body: Node2D) -> void:
	_handle_impact(body)

func _on_area_2d_area_entered(area: Area2D) -> void:
	_handle_impact(area)

# Free the node on all clients.
@rpc("authority","call_local","reliable")
func _queue_free() -> void:
	queue_free()
