extends Node2D
class_name Train

@export var num_cars: int = 8

var trackpaths: Array[PathFollow2D] = []
var traincars: Array[Node2D] = []

func _get_trackpath() -> Path2D:
	var p = get_parent()
	if p is Path2D:
		return p
	return null

func _get_configuration_warnings() -> PackedStringArray:
	if _get_trackpath() == null:
		return ["This scene must be the child of a Path2D."]
	return []

func _ready() -> void:
	# Add trains to track.
	var path: Path2D = _get_trackpath()
	for i in range(num_cars):
		var p: PathFollow2D = PathFollow2D.new()
		p.rotates = false
		path.add_child.call_deferred(p,true)
		trackpaths.append(p)
		var t
		if i == 0:
			t = load("res://train/train_front.tscn").instantiate()
		else:
			t = load("res://train/train_car.tscn").instantiate()
		add_child.call_deferred(t,true)
		traincars.append(t)

func _process(delta: float) -> void:
	var old_angles: Array[float]
	for i in range(num_cars):
		old_angles.append(traincars[i].global_rotation)
	#if trackpaths[0].progress > 100: return
	trackpaths[0].progress += delta * 100
	# Update position of train cars.
	for i in range(1,num_cars):
		trackpaths[i].progress = trackpaths[i-1].progress - 64
	for i in range(num_cars):
		traincars[i].position = trackpaths[i].position
	# Update orientation of train cars along the track.
	# Keep joints as close together as possible
	var l: int = 25
	for i in range(num_cars):
		var p1: Vector2 = traincars[i].position
		var p2: Vector2 = traincars[i].position
		if i > 0:
			p1 = traincars[i-1].position + l * Vector2.from_angle(traincars[i-1].rotation)
		if i < num_cars-1:
			p2 = traincars[i+1].position - l * Vector2.from_angle(traincars[i+1].rotation)
		traincars[i].rotation = (p2-p1).angle()
