extends CanvasLayer

# Scale and offset for converting from track path coords to map overlay coords.
var _scale: float
var _offset: Vector2

# The cars being tracked on the map.
var _icons: Dictionary

func set_track (track: Track) -> void:
	# Create the map from the track path.
	var points: Array[Vector2] = []
	var xmin : float
	var xmax : float
	var ymin : float
	var ymax : float
	var curve: Curve2D = track.get_node("TrackPath").curve
	for i in range(curve.point_count):
		var point: Vector2 = curve.get_point_position(i)
		points.append(point)
		xmin = min(xmin,point.x)
		xmax = max(xmax,point.x)
		ymin = min(ymin,point.y)
		ymax = max(ymax,point.y)
	points.append(points[0])
	#var offset: Vector2 = Vector2(xmin,ymin)
	_scale = min(1920/(xmax-xmin),1080/(ymax-ymin)) * 0.25
	_offset = Vector2(xmax - 1890/_scale, ymin - 30/_scale)
	# Define 2 lines - inner and outer with different widths and colours - for doing an outline effect.
	var line1: Line2D = Line2D.new()
	var line2: Line2D = Line2D.new()
	for point in points:
		# want (xmax+offset.x)*scale = 1920
		# -> xmax+offset.x = 1920/scale
		# -> offset.x = 1920/scale - xmax
		line1.add_point((point-_offset)*_scale)
		line2.add_point((point-_offset)*_scale)
	#line1.antialiased = true
	line1.width = 20.0
	line1.default_color = Color.BLACK
	line1.joint_mode = Line2D.LINE_JOINT_ROUND
	#line2.antialiased = true
	line2.width = 10.0
	line2.default_color = Color.GRAY
	line2.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(line1)
	add_child(line2)
	#line2.antialiased = true

	# Add finish line.
	var finish_line: Sprite2D = Sprite2D.new()
	finish_line.texture = load("res://race-interface/finishline-icon.png")
	finish_line.position = line1.points[-1]
	add_child(finish_line)

	# Render the tiny icons for the participants.
	for car: Car in track.get_node("StartingPositions").get_children():
		if car.tinypic != null:
			var pic: Sprite2D = Sprite2D.new()
			pic.texture = load(car.tinypic.load_path)
			add_child(pic)
			_icons[car] = pic
			car.AHHH.connect(func () -> void:
				spin(pic)
			)

	# Initial positioning of icons.
	_update_icons()

func _update_icons () -> void:
	for car: Car in _icons.keys():
		var icon: Sprite2D = _icons[car]
		icon.position = (car.position-_offset) * _scale

# Update icon positions as game progresses.
func _process(_delta: float) -> void:
	_update_icons()

# Apply a rotation effect to an icon (e.g. when the car gets hit).
var _spinning: Dictionary[Sprite2D,bool] = {}
func spin (icon: Sprite2D) -> void:
	# Ignore if already spinning.
	if _spinning.get(icon,false) == true: return
	_spinning[icon] = true
	var tween: Tween = create_tween()
	tween.tween_property(icon, "rotation_degrees", 360, 0.5)
	await tween.finished
	icon.rotation = 0
	_spinning[icon] = false

# Move the specified car to the front of the display.
func move_to_front (car: Car) -> void:
	var icon: Sprite2D = _icons[car]
	icon.z_index += 1
