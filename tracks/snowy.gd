extends Track

@onready var _snow: Array[Node2D] = [$Snow/Group1,$Snow/Group2,$Snow/Group3]
var _snowrate: Array[Vector2] = [Vector2(-5.0,50.0),Vector2(4.0,40.0),Vector2(0.0,30.0)]
var _camera_modifier: Array[float] = [1.1,1.05,1.0]

# Keep track of camera position, to get relative motion.
# There's probably a better way to handle this?
var _previous_camera_pos: Vector2

func _process(delta: float) -> void:
	# Update snow positions based on fall rate and camera motion.
	var camera: Camera2D = get_viewport().get_camera_2d()
	var camera_motion: Vector2
	if camera != null:
		var camera_pos: Vector2 = camera.get_screen_center_position()
		camera_motion = camera_pos - _previous_camera_pos
		_previous_camera_pos = camera_pos
	else:
		camera_motion = Vector2.ZERO
	for i in range(len(_snow)):
		var pos: Vector2 = _snow[i].position
		# Falling snow
		pos += _snowrate[i] * delta
		# Camera motion
		pos -= camera_motion * _camera_modifier[i]
		# Wrap snow around.
		# Could probably do something more robust with tiling?
		# But this works for now.
		while pos.x < -960: pos.x += 1920
		while pos.x > 960: pos.x -= 1920
		while pos.y < -540: pos.y += 1080
		while pos.y > 540: pos.y -= 1080
		_snow[i].position = pos
