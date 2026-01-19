extends Area2D

# Item blocks.

# Note: Using RPC calls instead of a MultiplayerSynchronizer for the item state, because
# the synchronizer doesn't seem to work properly from the TileMapLayer where these
# items are stored.

func _on_body_entered(body: Node2D) -> void:
	collision_mask = 0
	collision_layer = 0
	$ParticleTimer.start()
	$RespawnTimer.start()
	$ReactivateTimer.start()
	if "get_itemblock" in body:
		body.get_itemblock()
	_item_taken_visual.rpc()
@rpc("authority","reliable","call_local")
func _item_taken_visual() -> void:
	$AnimatedSprite2D.modulate = Color.hex(0xffffff00)
	$CPUParticles2D.emitting = true
	$AudioStreamPlayer2D.play()

func _on_particle_timer_timeout() -> void:
	_item_particle_stop.rpc()
@rpc("authority","reliable","call_local")
func _item_particle_stop() -> void:
	$CPUParticles2D.emitting = false

func _on_respawn_timer_timeout() -> void:
	_item_reappear.rpc()
@rpc("authority","reliable","call_local")
func _item_reappear() -> void:
	var tween: Tween = create_tween()
	tween.tween_property($AnimatedSprite2D, "modulate", Color.WHITE, 1.0)
	await tween.finished

func _on_reactivate_timer_timeout() -> void:
	collision_layer = 1
	collision_mask = 1
