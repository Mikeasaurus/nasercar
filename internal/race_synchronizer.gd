extends MultiplayerSynchronizer

class_name RaceSynchronizer

# Extension of MultiplayerSynchronizer to handle subgroups of peers within a race.

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Get peers to synchronize with (server-side setup only).
	if multiplayer.get_unique_id() != 1: return
	# Find the ancestor node with the race participant information.
	var node = self
	while node != null and "participants" not in node:
		node = node.get_parent()
	# Only need to synchronize with participating peers.
	if node == null: return
	for peer in node.participants.keys():
		set_visibility_for(peer,true)
