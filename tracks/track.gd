extends Node2D

class_name Track

## Number of laps for the track.
@export var laps: int = 1

## Description of the track.
@export_multiline var description: String

## Thumbnail for track
@export var thumbnail_image: CompressedTexture2D

# Finalize some setup, such as item block interactions.
func _ready () -> void:
	# Force the TileMapLayer to instantiate its scenes, because normally this is deferred and we can't
	# see the sprites from this _ready() function.
	var items: TileMapLayer = get_node("TilesAboveCars/Items")
	if items != null:
		items.update_internals()
		# Use consistent names for the items.
		# The auto-generated names can quickly get out of sync between client/server.
		# Copied this solution from SlimeTime, where I was having the same problem.
		for c in items.get_children():
			c.name = c.scene_file_path.split('/')[-1].split('.')[0]+"_"+str(c.position.x)+"_"+str(c.position.y)
