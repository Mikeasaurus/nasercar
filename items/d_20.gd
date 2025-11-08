extends Area2D

# Item blocks.

# Note: Using RPC calls instead of a MultiplayerSynchronizer for the item state, because
# the synchronizer doesn't seem to work properly from the TileMapLayer where these
# items are stored.
# Keep a list of peers to send the RPC calls to.
var peers: Array = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	multiplayer.multiplayer_peer.peer_disconnected.connect(_player_disconnected)

func _on_body_entered(body: Node2D) -> void:
	collision_mask = 0
	collision_layer = 0
	$ParticleTimer.start()
	$RespawnTimer.start()
	$ReactivateTimer.start()
	if "get_itemblock" in body:
		body.get_itemblock()
	for peer in peers:
		_item_taken_visual.rpc_id(peer)
@rpc("authority","reliable","call_local")
func _item_taken_visual() -> void:
	$AnimatedSprite2D.modulate = Color.hex(0xffffff00)
	$CPUParticles2D.emitting = true
	$AudioStreamPlayer2D.play()

func _on_particle_timer_timeout() -> void:
	for peer in peers:
		_item_particle_stop.rpc_id(peer)
@rpc("authority","reliable","call_local")
func _item_particle_stop() -> void:
	$CPUParticles2D.emitting = false

func _on_respawn_timer_timeout() -> void:
	for peer in peers:
		_item_reappear.rpc_id(peer)
@rpc("authority","reliable","call_local")
func _item_reappear() -> void:
	var tween: Tween = create_tween()
	tween.tween_property($AnimatedSprite2D, "modulate", Color.WHITE, 1.0)
	await tween.finished

func _on_reactivate_timer_timeout() -> void:
	collision_layer = 1
	collision_mask = 1

# Update peer list when a peer disconnects, or get spurrious errors in the console about unknown peer ids.
func _player_disconnected (player_id: int) -> void:
	if player_id in peers:
		peers.erase(player_id)
