extends RigidBody2D
class_name Car

## What name to use for display on screen.
@export var display_name: String = "???"

## Picture of character for car selection.
## Multiple images can be added for an animated effect.
@export var headshot: Array[CompressedTexture2D]

## Thumbnail image for map overlay.
@export var tinypic: CompressedTexture2D

## Top speed of car (pixels/second)
@export var max_speed: float = 1500.0

## Acceleration (pixels/second/second)
@export var acceleration: float = 500.0

## Drag (as deceleration)
@export var deceleration: float = acceleration/3

## Brake power (pixels/second/second)
@export var brakes: float = acceleration*2

## How far the wheels can turn in one direction (degrees)
@export var max_wheel_angle: float = 30.0

## How fast the wheels can turn (degrees/sec)
@export var wheel_turn_speed: float = 120.0

## Emit signal when an item block is touched.
signal itemblock
func get_itemblock () -> void:
	itemblock.emit()

## Emit signal when meteor impacts.
signal meteor_impact

## Emit signal when completing a lap.
signal lap_completed (lap: int)
var _current_lap: int
# Remember previous progress along the track, to help detect when a lap is completed
# (when the PathFollow2D progress loops around).
var _last_progress: float

## Emit signal when this car gets in trouble (bonked by beetle, sinking in water, etc.)
## Can be used for applying visual effects to other elements of the game.
signal AHHH

## Effects currently applied to the car
enum EffectType {SLIMED,NAILPOLISHED,CAFFEINATED,SMOULDERING}
var effects: Dictionary = {}

## Effects applied to individual wheels.
@onready var wheels: Array[Node2D] = [$Wheels/FrontLeft, $Wheels/FrontRight, $Wheels/RearLeft, $Wheels/RearRight]
var wheel_skidmarks: Array[SkidMark] = [null, null, null, null]
var wheel_effects: Array[Dictionary] = [{},{},{},{}]

# Tilesets of the world.
# Need a reference to them to query for physics parameters and other effects.
var _tilesets: Array[TileMapLayer]

# Friction modifier (for changing value during a collision.)
var collision_friction_modifier: float = 1.0

## Whether this car is allowed to move.
var moveable: bool = false

## Car controls.
## Inputs captured from client side, and sent to server side via RPC calls.
var controllable: bool = false
#
var _turning_left: bool = false
@rpc("any_peer","reliable","call_local")
func _press_left () -> void:
	_turning_left = true
@rpc("any_peer","reliable","call_local")
func _unpress_left () -> void:
	_turning_left = false
#
var _turning_right: bool = false
@rpc("any_peer","reliable","call_local")
func _press_right () -> void:
	_turning_right = true
@rpc("any_peer","reliable","call_local")
func _unpress_right () -> void:
	_turning_right = false
#
var _accelerating: bool = false
@rpc("any_peer","reliable","call_local")
func _press_up () -> void:
	_accelerating = true
@rpc("any_peer","reliable","call_local")
func _unpress_up () -> void:
	_accelerating = false
#
var _braking: bool = false
@rpc("any_peer","reliable","call_local")
func _press_space () -> void:
	_braking = true
@rpc("any_peer","reliable","call_local")
func _unpress_space () -> void:
	_braking = false
#
var _reversing: bool = false
@rpc("any_peer","reliable","call_local")
func _press_down () -> void:
	_reversing = true
@rpc("any_peer","reliable","call_local")
func _unpress_down () -> void:
	_reversing = false
#
@rpc("any_peer","reliable","call_local")
func _touchpad_press (touch_position: Vector2) -> void:
	var t: Vector2 = touch_position - global_position
	var w: Vector2 = Vector2.from_angle($Wheels/FrontLeft.global_rotation).rotated(PI/2)
	var angle: float = w.angle_to(t)/PI*180
	if angle < 0:
		_turning_left = true
		_turning_right = false
	elif angle > 0:
		_turning_right = true
		_turning_left = false
	if w.dot(t) >= 0:
		_accelerating = true
		_reversing = false
	else:
		_reversing = true
		_accelerating = false
#
@rpc("any_peer","reliable","call_local")
func _touchpad_unpress () -> void:
	_unpress_left.rpc_id(1)
	_unpress_right.rpc_id(1)
	_unpress_up.rpc_id(1)
	_unpress_down.rpc_id(1)
#
func _input(event: InputEvent) -> void:
	if not controllable: return
	if event.is_action_pressed("turn_left"):
		_press_left.rpc_id(1)
	if event.is_action_released("turn_left"):
		_unpress_left.rpc_id(1)
	if event.is_action_pressed("turn_right"):
		_press_right.rpc_id(1)
	if event.is_action_released("turn_right"):
		_unpress_right.rpc_id(1)
	if event.is_action_pressed("go"):
		_press_up.rpc_id(1)
	if event.is_action_released("go"):
		_unpress_up.rpc_id(1)
	if event.is_action_pressed("stop"):
		_press_space.rpc_id(1)
	if event.is_action_released("stop"):
		_unpress_space.rpc_id(1)
	if event.is_action_pressed("reverse"):
		_press_down.rpc_id(1)
	if event.is_action_released("reverse"):
		_unpress_down.rpc_id(1)

enum CarType {PLAYER, CPU, REMOTE}

## Type of car
var type: CarType = CarType.REMOTE

## Type of CPU movement.
## Normally, always moving forward unless needing to get unstuck.
enum CPU_Movement {FORWARD,BACKWARD}
var cpu_movement: CPU_Movement = CPU_Movement.FORWARD
enum CPU_Steer_Direction {PATH, LEFT, CENTRE, RIGHT}
var cpu_steer_direction: CPU_Steer_Direction = CPU_Steer_Direction.PATH
## Check if CPU car is stuck (not moving forward).
var _is_stuck: bool = false
var _stuck_since: float
var _getting_unstuck: bool = false

## The path to follow if this is a CPU.
var _pathfollow: PathFollow2D = null
# For tracking player progress along path.
var _old_path_pos: Vector2 = Vector2.ZERO
# For restoring proper offset after wavering effect
var _path_offset: float

# For playing crashing sound.
var _crashing: bool = false
# For sinking into water and playing splash sound.
var _splashing: bool = false

## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Raise the z_index so effects like skid marks appear beneath it.
	z_index = 2

# Called to show a nameplace on the car.
func show_nameplate (text: String) -> void:
	$Nameplate.show()
	$Nameplate.text = text
func hide_nameplate () -> void:
	$Nameplate.hide()

# Add track information (world tiles, path from start to finish of race).
func add_to_track (track_path: Path2D, tilesets: Array[TileMapLayer]) -> void:
	_tilesets = tilesets
	type = CarType.REMOTE
	_pathfollow = PathFollow2D.new()
	track_path.add_child(_pathfollow)
	var offset: Vector2 = global_position - (track_path.global_position+track_path.curve.get_point_position(0))
	#TODO: more robost with starting orientation.
	_pathfollow.v_offset = offset.x
	# Remember this offset in case we need to shift the path for wavering effect.
	_path_offset = _pathfollow.v_offset
	# Starting on first lap.
	_current_lap = 1
	_last_progress = 0

# Let this car be playable by the local user.
func make_local_playable () -> void:
	type = CarType.PLAYER
	controllable = true
	$Camera2D.enabled = true
	$Arrow.show()
	# Make own engine sound louder.
	$EngineSound.volume_db = 1.0

# Let this car be playable in a multiplayer game.
# (input controls captured locally, but car managed by server).
@rpc("authority","reliable")
func make_remote_playable_clientside () -> void:
	# Turn off local collision detection for remotely managed cars.
	collision_mask = 0
	collision_layer = 0
	type = CarType.REMOTE
	controllable = true
	$Camera2D.enabled = true
	$Arrow.show()
	# Make own engine sound louder.
	$EngineSound.volume_db = 1.0
func make_remote_playable_serverside () -> void:
	type = CarType.PLAYER

# Override player controls with autopilot.
# (for after end of race).
func autopilot () -> void:
	type = CarType.CPU
	$Arrow.hide()

# Make this car follow a predetermined path
# (as local CPU).
func make_local_cpu () -> void:
	type = CarType.CPU

# Make this car an entirely remotely controlled car,
# with no input captured from the user.
@rpc("authority","reliable")
func make_remote () -> void:
	# Turn off local collision detection for remotely managed cars.
	collision_mask = 0
	collision_layer = 0
	type = CarType.REMOTE

# Allow this car to start moving.
func go () -> void:
	moveable = true

# Stop this car from moving.
func stop () -> void:
	moveable = false

# Get current progress of the car, taking laps into account.
func progress () -> float:
	var lap: int = _current_lap
	var prog1: float = _last_progress
	var prog2: float = _pathfollow.progress_ratio
	if prog2 < prog1:
		lap += 1
	return (lap-1) + prog2

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# Arrow pointing to player needs to stay oriented upward.
	$Arrow.global_rotation = 0
	$Arrow.scale = 2*Vector2(1/$Camera2D.zoom.x, 1/$Camera2D.zoom.y)
	$Arrow.offset.y = -60*$Camera2D.zoom.y
	# Same with smouldering effects.
	$Meteor.global_rotation = 0
	# Same with nameplate.
	if $Nameplate.visible:
		$Nameplate.rotation = $Arrow.rotation
		$Nameplate.global_position = global_position + Vector2(-$Nameplate.size.x/2,-110)
	# And ice break effect.
	$Iced/CPUParticles2D.global_rotation = 0

	#######################################################
	# Handle touch controls.
	#######################################################
	# Done early in _process, since it has to be handled on client side and the
	# rest of this routine is for server side stuff.
	if controllable and DisplayServer.is_touchscreen_available():
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_touchpad_press.rpc_id(1,get_global_mouse_position())
		else:
			_touchpad_unpress.rpc_id(1)
			_unpress_left.rpc_id(1)
			_unpress_right.rpc_id(1)
			_unpress_up.rpc_id(1)
			_unpress_down.rpc_id(1)

	# The rest of this code is for server-side processing.
	if type == CarType.REMOTE: return

	#######################################################
	# Check if a lap was just completed.
	#######################################################
	if _last_progress > _pathfollow.progress_ratio:
		lap_completed.emit(_current_lap)
		set_deferred("_current_lap", _current_lap+1)
	_last_progress = _pathfollow.progress_ratio

	#######################################################
	# Apply effects
	#######################################################
	# CPU cars waver around when slimed.
	if EffectType.SLIMED in effects:
		_pathfollow.v_offset = _path_offset + 200*sin((Time.get_ticks_msec()%1000)/1000. * 2*PI)
	else:
		_pathfollow.v_offset = _path_offset
	# Smouldering cars have effects applied.
	var smoulder_speed_limiter: float = 1.0
	var smoulder_drag: float = 1.0
	if EffectType.SMOULDERING in effects:
		var smoulder_duration: float = Time.get_ticks_msec() - effects[EffectType.SMOULDERING]
		var modulated_stuff: Array = [$Body, $Wheels/FrontLeft/Sprite2D, $Wheels/FrontRight/Sprite2D, $Wheels/RearLeft/Sprite2D, $Wheels/RearRight/Sprite2D]
		if smoulder_duration < 3000:
			for m in modulated_stuff:
				m.modulate = Color.BLACK
			if not $Meteor/CPUParticles2D.emitting:
				$Meteor/CPUParticles2D.emitting = true
			smoulder_speed_limiter = 0.0
			smoulder_drag = 7.0
		elif smoulder_duration < 6000:
			var c: float = (smoulder_duration-3000)/3000
			for m in modulated_stuff:
				m.modulate = Color(c,c,c)
			smoulder_speed_limiter = c
		else:
			for m in modulated_stuff:
				m.modulate = Color.WHITE
			$Meteor/CPUParticles2D.emitting = false
			effects.erase(EffectType.SMOULDERING)
	
	var dr: float = wheel_turn_speed * delta / 180 * PI
	var max_r: float = max_wheel_angle / 180 * PI

	#######################################################
	# Get CPUs unstuck.
	#######################################################
	if type == CarType.CPU and moveable and not _getting_unstuck and EffectType.SMOULDERING not in effects:
		if linear_velocity.length() < 10:
			# Just starting to be stuck (or just speeding up from a stop)
			if not _is_stuck:
				_is_stuck = true
				_stuck_since = Time.get_ticks_msec()
			# If not moving for a while, then probably stuck.
			elif Time.get_ticks_msec() - _stuck_since > 3000:
				_get_unstuck()
		else:
			_is_stuck = false

	#######################################################
	# Compute the progress of the car along the path.
	#######################################################
	if _pathfollow != null:
		# Check if "progress" is needed for updating the path.
		var distance_to_path: float = (global_position-_pathfollow.global_position).length()
		# If next point along path is closer to player than previous point, then update to that point.
		if distance_to_path < (global_position-_old_path_pos).length():
			_old_path_pos = _pathfollow.global_position
			_pathfollow.progress += 300


	#######################################################
	# Path-following for CPUs
	#######################################################
	if type == CarType.CPU and cpu_steer_direction == CPU_Steer_Direction.PATH:
		# Make sure our target point is far enough ahead.
		var target_direction: Vector2 = _pathfollow.global_position - global_position
		var angle: float = target_direction.angle() - global_rotation
		for wheel in [$Wheels/FrontLeft, $Wheels/FrontRight]:
			# Target angle of wheel (from wheel frame of reference).
			var target_angle: float = target_direction.angle() - PI/2 - rotation
			# Difference in angle between wheel and target path.
			var angle_diff: float = target_angle - wheel.rotation
			if angle_diff >= PI: angle_diff -= 2*PI
			elif angle_diff <= -PI: angle_diff += 2*PI
			if angle_diff < 0:
				if wheel.rotation > -max_r:
					wheel.rotation -= dr
			elif angle_diff > 0:
				if wheel.rotation < max_r:
					wheel.rotation += dr

	#######################################################
	# Directional arrow for lost player
	#######################################################
	# (So player can be returned to road when something happens to their car).
	if type == CarType.PLAYER:
		var distance_to_path: float = (global_position-_pathfollow.global_position).length()
		# Point to where player was last on the path, if they wandered too far.
		$LostArrow.global_rotation = (_pathfollow.global_position-global_position).angle() + PI/2
		if distance_to_path > 2000:
			if not $LostArrow.visible:
				$LostArrow/Fade.play("fade_in")
		elif distance_to_path < 500 and $LostArrow.visible:
			$LostArrow/Fade.play("fade_out")
	# If not a player anymore (e.g. just finished race), make sure arrow is hidden.
	if type != CarType.PLAYER and $LostArrow.visible:
		$LostArrow.hide()

	#######################################################
	# Wheel-turning for player or override of regular CPU steering
	#######################################################
	var turn_left: bool = false
	var turn_right: bool = false
	var recenter: bool = false
	# Determine if wheels need to be turned, and in which direction.
	if type == CarType.PLAYER or (type == CarType.CPU and cpu_steer_direction != CPU_Steer_Direction.PATH):
		# Turn left
		if (type == CarType.PLAYER and _turning_left) or cpu_steer_direction == CPU_Steer_Direction.LEFT:
			turn_left = true
		# Turn right
		elif (type == CarType.PLAYER and _turning_right) or cpu_steer_direction == CPU_Steer_Direction.RIGHT:
			turn_right = true
		# Re-center
		else:
			recenter = true

	if turn_left:
		for wheel in [$Wheels/FrontLeft, $Wheels/FrontRight]:
			if wheel.rotation > -max_r:
				wheel.rotation -= dr
	elif turn_right:
		for wheel in [$Wheels/FrontLeft, $Wheels/FrontRight]:
			if wheel.rotation < max_r:
				wheel.rotation += dr
	elif recenter:
		for wheel in [$Wheels/FrontLeft, $Wheels/FrontRight]:
			if wheel.rotation < 0:
				wheel.rotation += 2*dr
			elif wheel.rotation > 0:
				wheel.rotation -= 2*dr
			if abs(wheel.rotation) <= 2*dr:
				wheel.rotation = 0


	#######################################################
	# Movement
	#######################################################
	var go_pressed: bool = _accelerating
	var stop_pressed: bool = _braking
	var reverse_pressed: bool = _reversing
	# Check for speed modifiers.
	var acceleration_modifier: float = 1.0
	var max_speed_modifier: float = 1.0
	var friction_modifier: float = 1.0
	if EffectType.CAFFEINATED in effects:
		if Time.get_ticks_msec() <= effects[EffectType.CAFFEINATED] + 5000:
			acceleration_modifier *= 5.0
			max_speed_modifier *= 2.0
			friction_modifier *= 2.0
		else:
			$Coffee/CPUParticles2D.emitting = false
			effects.erase(EffectType.CAFFEINATED)
	# Keep track of how fast wheels are spinning (fastest one).
	# Value is used for things like zoom level and engine pitch.
	var fastest_wheel_speed: float = 0.0
	# Check if any wheels end up skidding, so a sound can play.
	var skidding: bool = false
	var skid_sounds: Array[bool] = [false,false,false,false]
	var sinking: bool = true  # becomes false if any wheel on solid ground.
	var liquid_type: int  # Type of liquid the car is sinking into (if sinking).
	for w in range(len(wheels)):
		var wheel: Node2D = wheels[w]
		# Velocity of point where wheel connects to car
		var wheel_velocity: Vector2 = linear_velocity + wheel.position.rotated(rotation+PI/2) * angular_velocity
		# Direction that wheel is pointing.
		var wheel_direction: Vector2 = Vector2.from_angle(wheel.global_rotation + PI/2)
		var wheel_orthogonal_direction: Vector2 = Vector2.from_angle(wheel.global_rotation)
		# Infer current wheel speed based on speed w.r.t. ground.
		var current_speed: float = wheel_velocity.dot(wheel_direction)
		# Update speed based on user input.
		var new_speed: float = current_speed
		# Player hitting the gas, or CPU (which always hits gas).
		var f: Vector2 = Vector2.ZERO
		if moveable:
			if (type == CarType.PLAYER and go_pressed) or (type == CarType.CPU and cpu_movement == CPU_Movement.FORWARD):
				if new_speed < max_speed * max_speed_modifier * smoulder_speed_limiter:
					new_speed += acceleration * acceleration_modifier * delta
			# Player hitting the brakes?
			elif (type == CarType.PLAYER and stop_pressed):
				if new_speed > 0: new_speed -= brakes * delta
				elif new_speed < 0: new_speed += brakes * delta
				# To avoid "quivering"
				if abs(new_speed) < brakes * delta: new_speed = current_speed * 0.5
			# Player backing up?
			elif (type == CarType.PLAYER and reverse_pressed) or (type == CarType.CPU and cpu_movement == CPU_Movement.BACKWARD):
				if new_speed > -max_speed * max_speed_modifier * smoulder_speed_limiter:
					new_speed -= acceleration * acceleration_modifier * delta
			# Slow down from air drag.
			#else:
			if true:
				if new_speed > 0: new_speed -= deceleration * smoulder_drag * delta
				elif new_speed < 0: new_speed += deceleration * smoulder_drag * delta
				# To avoid "quivering"
				if abs(new_speed) < deceleration * delta: new_speed = current_speed * 0.5
			# Keep track of fastest wheel, the speed will be used for other things
			# further down.
			if abs(new_speed) > fastest_wheel_speed:
				fastest_wheel_speed = abs(new_speed)
			# Calculate the force to apply to get the wheel to the new speed.
			f = mass/4.0 * (new_speed-current_speed) / delta * wheel_direction
		
		# Apply friction force orthogonal to wheel direction.
		current_speed = wheel_velocity.dot(wheel_orthogonal_direction)
		var mag: float = mass/4.0 * current_speed/delta
		# Dampen the magnitude so it's not a completely sudden stop in a single timestep.
		# That would case some weird glitching.
		mag *= 0.5
		# Combine static friction force and force of motion from engine.
		f += mag * -wheel_orthogonal_direction

		#######################################################
		# Skid marks / special effects for wheel.
		#######################################################
		# Get wheel special effects.
		# Check if car is currently in a nail polish puddle.
		# If it is, check which wheels are in the puddle.
		var t: float = Time.get_ticks_msec()
		if EffectType.NAILPOLISHED in effects:
			for np in effects[EffectType.NAILPOLISHED].values():
				var pos: Vector2 = np[0]
				var rad: float = np[1]
				var c: Color = np[2]
				if (wheel.global_position-pos).length() <= rad:
					wheel_effects[w][EffectType.NAILPOLISHED] = [c,t]
		# Clear out old wheel effects.
		if EffectType.NAILPOLISHED in wheel_effects[w]:
			# Nail polish wears off after 1 second.
			var expire: float = wheel_effects[w][EffectType.NAILPOLISHED][1]+1000.0
			if t >= expire:
				wheel_effects[w].erase(EffectType.NAILPOLISHED)
				
		# Limit the static friction force magnitude.
		# First, get auxiliary data about the ground surface.
		var friction: float = 1.0
		var skidmark_colour: Color = Color.TRANSPARENT
		var particle_colour_1: Color = Color.TRANSPARENT
		var particle_colour_2: Color = Color.TRANSPARENT
		var dusty: bool = false
		var wheel_sinking: bool
		var skid_sound: int
		var wheel_global_position: Vector2 = wheel.global_position
		for tilesource in _tilesets:
			if tilesource == null: continue
			var tilepos: Vector2i = tilesource.local_to_map((wheel_global_position-tilesource.global_position)/tilesource.scale.x)
			var tiledata: TileData = tilesource.get_cell_tile_data(tilepos)
			if tiledata == null: continue
			if tiledata.get_custom_data("has_skidmarks"):
				# Handle tiles that only give partial coverage.
				if tiledata.get_custom_data("is_partial"):
					var partial_type: int = tiledata.get_custom_data("partial_type")
					var dx: float = tilesource.tile_set.tile_size.x * tilesource.scale.x
					var origin: Vector2
					# 1,2,3,4 = quarter circles
					if partial_type == 1:
						origin = (tilesource.map_to_local(tilepos)) * tilesource.scale.x + Vector2(dx/2,dx/2) + tilesource.global_position
					if partial_type == 2:
						origin = (tilesource.map_to_local(tilepos)) * tilesource.scale.x + Vector2(-dx/2,dx/2) + tilesource.global_position
					if partial_type == 3:
						origin = (tilesource.map_to_local(tilepos)) * tilesource.scale.x + Vector2(dx/2,-dx/2) + tilesource.global_position
					if partial_type == 4:
						origin = (tilesource.map_to_local(tilepos)) * tilesource.scale.x + Vector2(-dx/2,-dx/2) + tilesource.global_position
					if (wheel_global_position - origin).length() > dx:
						continue
				skidmark_colour = tiledata.get_custom_data("skidmark_colour")
			if tiledata.get_custom_data("has_particles"):
				particle_colour_1 = tiledata.get_custom_data("particle_colour_1")
				particle_colour_2 = tiledata.get_custom_data("particle_colour_2")
			else:
				# Turn off particles if layer on top doesn't have them.
				# E.g., paved road on top of grass tile.
				particle_colour_1 = Color.TRANSPARENT
				particle_colour_2 = Color.TRANSPARENT
			dusty = tiledata.get_custom_data("is_dusty")
			skid_sound = tiledata.get_custom_data("skid_sound")
			friction = tiledata.get_custom_data("friction")
			# Check if wheel is in water.
			if tiledata.get_custom_data("is_liquid"):
				wheel_sinking = true
				liquid_type = tiledata.get_custom_data("liquid_type")
			else:
				wheel_sinking = false
		# Special effects override the tile skidmarks and friction.
		if EffectType.NAILPOLISHED in wheel_effects[w] and not wheel_sinking:
			skidmark_colour = wheel_effects[w][EffectType.NAILPOLISHED][0]
			if w%2 == 1: friction = 0
			else: friction = -0.3
		# Add skid marks and particle effects.
		var max_static_friction = mass*acceleration*friction*friction_modifier*collision_friction_modifier
		var p1: CPUParticles2D = wheel.get_node("Particles1")
		var p2: CPUParticles2D = wheel.get_node("Particles2")
		var dust: CPUParticles2D = wheel.get_node("Dust")
		if f.length() > max_static_friction:
			f = f.limit_length(max_static_friction)
			if skidmark_colour != Color.TRANSPARENT:
				skidding = true
				if wheel_skidmarks[w] == null or wheel_skidmarks[w].default_color != skidmark_colour:
					wheel_skidmarks[w] = load("res://cars/skid_mark.tscn").instantiate()
					wheel_skidmarks[w].default_color = skidmark_colour
					add_sibling(wheel_skidmarks[w],true)
					wheel_skidmarks[w].z_index = 1
				wheel_skidmarks[w].add_point(wheel_global_position - global_position + position)
			else:
				wheel_skidmarks[w] = null
			if particle_colour_1 != Color.TRANSPARENT:
				p1.color = particle_colour_1
				p1.emitting = true
			else:
				p1.emitting = false
			if particle_colour_2 != Color.TRANSPARENT:
				p2.color = particle_colour_2
				p2.emitting = true
			else:
				p2.emitting = false
			if dusty:
				dust.emitting = true
			else:
				dust.emitting = false
		else:
			wheel_skidmarks[w] = null
			p1.emitting = false
			p2.emitting = false
			dust.emitting = false

		if not wheel_sinking:
			sinking = false  # car not sinking if any wheel is on solid ground.

		apply_force(f, wheel.position.rotated(rotation))

		skid_sounds[skid_sound] = true

	if skidding and skid_sounds[1]:
		if not $TireSquealSound.playing:
			$TireSquealSound.play(2.0)
	if skidding and skid_sounds[2]:
		if not $GravelSound.playing:
			$GravelSound.play()
	if skidding and skid_sounds[3]:
		if not $GratingSound.playing:
			$GratingSound.play()
	if not skidding or not skid_sounds[1]:
		if $TireSquealSound.playing:
			$TireSquealSound.stop()
	if not skidding or not skid_sounds[2]:
		if $GravelSound.playing:
			$GravelSound.stop()
	if not skidding or not skid_sounds[3]:
		if $GratingSound.playing:
			$GratingSound.stop()

	if sinking:
		_kersplash(liquid_type)

	#######################################################
	# Zoom out camera the faster the car is going.
	#######################################################
	var z: float = 2.0 / (1 + 2*fastest_wheel_speed / max_speed)
	var zoom_limit: float = 0.1 * delta
	if z < $Camera2D.zoom.x:
		$Camera2D.zoom.x = z
		$Camera2D.zoom.y = z
	# When car slowing down, zoom back in.
	# But limit speed of zoom to avoid issues when speed suddenly drops.
	elif z-zoom_limit > $Camera2D.zoom.x:
		$Camera2D.zoom.x += zoom_limit
		$Camera2D.zoom.y += zoom_limit
	else:
		$Camera2D.zoom.x = z
		$Camera2D.zoom.y = z
		

	#######################################################
	# Engine sound
	#######################################################
	if fastest_wheel_speed <= 0.05 * max_speed:
		$EngineSound.pitch_scale = 0.5
	else:
		$EngineSound.pitch_scale = 1 + fastest_wheel_speed / max_speed

func _on_body_entered(_body: Node) -> void:
	if _crashing: return  # Only play sound once during a crashing period.
	_crash_effect()
	_crashing = true
	# If CPU car is hitting another car from behind, then it honks its horn :3
	if type == CarType.CPU and _body is Car and not $HornSound.playing:
		# When it's 2 CPU cars colliding, the one behind does the honking.
		if Vector2.from_angle(global_rotation+PI/2).dot(_body.position-self.position) > 0:
			$HornSound.play()
		# CPU car will always honk when it hits a player car.
		elif _body.type == CarType.PLAYER:
			$HornSound.play()

func _crash_effect(stun_duration: float = 1.0) -> void:
	$CrashSound.play()
	$CrashSoundTimer.start()
	var tween: Tween = create_tween()
	collision_friction_modifier = 0.0
	tween.tween_property(self, "collision_friction_modifier", 1.0, stun_duration)

func _on_crash_sound_timer_timeout() -> void:
	_crashing = false

# Make car splash into water
func _kersplash (liquid_type: int) -> void:
	var splash: Node2D
	var sound: AudioStreamPlayer2D
	var particles: CPUParticles2D
	var dt: float
	match liquid_type:
		0:
			splash = $WaterSplash
			sound = $WaterSplash/SplashSound
			particles = $WaterSplash/Particles
			dt = 0.3
		1:
			splash = $LavaSplash
			sound = $LavaSplash/SplashSound
			particles = $LavaSplash/Particles
			dt = 0.6
		2:
			splash = $IcyWaterSplash
			sound = $IcyWaterSplash/SplashSound
			particles = $IcyWaterSplash/Particles
			dt = 0.3
	# Only run this once when sinking, not on every tick.
	if _splashing: return
	_splashing = true
	scream()
	# Stop car from moving any further during this sequence.
	freeze = true
	# Car not moveable (turns off other skidding / particle effects from friction).
	moveable = false
	# Start showing ripple of water when car is sinking.
	# Also fade the car into the water.
	splash.global_rotation = 0
	_ripples.rpc(liquid_type)
	var tween: Tween = create_tween()
	var dr: float = 0.20
	var modulated_stuff: Array = [$Body, $Wheels/FrontLeft/Sprite2D, $Wheels/FrontRight/Sprite2D, $Wheels/RearLeft/Sprite2D, $Wheels/RearRight/Sprite2D, $Slimed, $Coffee]
	for m in modulated_stuff:
		tween.parallel().tween_property(m, "modulate", Color.hex(0x00000000), dt)
	# Start playing splashing sound as well.
	sound.play(0.3)
	await tween.finished
	# Near end of inward convergence of water, show spray of water particles.
	particles.emitting = true
	await get_tree().create_timer(dt*dr*2, false).timeout
	particles.emitting = false
	# Cut off sound before second splash in the .wav file.
	await get_tree().create_timer(1.0, false).timeout
	sound.stop()
	# Move car back onto the road.
	await _move_to_road ()
	# Post-splash effects?
	if liquid_type == 1:
		smoulder()
	# Otherwise, just restore normal modulation.
	else:
		for m in modulated_stuff:
			m.modulate = Color.WHITE
	# Delay on car movement for special effect (such as frozen?)
	# No car motion during this (unlike smoulder), so don't need to put this
	# in the more complicated "effects" logic.
	if liquid_type == 2:
		$Iced/Ice.show()
		await get_tree().create_timer(1.0, false).timeout
		$Iced/Ice.hide()
		$Iced/CPUParticles2D.emitting = true
		$Iced/ShatterSound.play()
	# Make car mobile again.
	freeze = false
	# Reset stuck detection timer to avoid triggereing "un-stuck" maneuver.
	# We haven't been stuck this whole time, just occupied.
	_stuck_since = Time.get_ticks_msec()
	moveable = true
	# Done
	_splashing = false
# Need to manage ripple effect via RPC, since gradient properties can't be
# managed in a MultiplayerSynchronizer.
@rpc("authority","reliable","call_local")
func _ripples (liquid_type: int) -> void:
	var ripple: Node2D
	var ripple_light: TextureRect
	var ripple_dark: TextureRect
	var dt: float
	match liquid_type:
		0:
			ripple = $WaterSplash/Ripple
			ripple_light = $WaterSplash/Ripple/Light
			ripple_dark = $WaterSplash/Ripple/Dark
			dt = 0.3
		1:
			ripple = $LavaSplash/Ripple
			ripple_light = $LavaSplash/Ripple/Light
			ripple_dark = $LavaSplash/Ripple/Dark
			dt = 0.6
		2:
			ripple = $IcyWaterSplash/Ripple
			ripple_light = $IcyWaterSplash/Ripple/Light
			ripple_dark = $IcyWaterSplash/Ripple/Dark
			dt = 0.3
	ripple.show()
	var dr: float = 0.20
	var tween: Tween = create_tween()
	var start: PackedFloat32Array = PackedFloat32Array([0,1-2*dr,1-dr,1,1])
	var almost: PackedFloat32Array = PackedFloat32Array([0,0,dr,2*dr,1])
	var finish: PackedFloat32Array = PackedFloat32Array([0,0,0,dr,1])
	ripple_dark.texture.gradient.offsets = start
	ripple_light.texture.gradient.offsets = start
	tween.tween_property(ripple_dark.texture.gradient, "offsets", almost, dt)
	tween.parallel().tween_property(ripple_light.texture.gradient, "offsets", almost, dt)
	#TODO
	await tween.finished
	tween = create_tween()
	tween.tween_property(ripple_dark.texture.gradient, "offsets", finish, dt*dr*2)
	tween.parallel().tween_property(ripple_light.texture.gradient, "offsets", finish, dt*dr*2)
	tween.parallel().tween_property(ripple_dark, "modulate", Color.TRANSPARENT, dt*dr*2)
	tween.parallel().tween_property(ripple_light, "modulate", Color.TRANSPARENT, dt*dr*2)
	await tween.finished
	ripple.hide()
	ripple_dark.modulate = Color.WHITE
	ripple_light.modulate = Color.WHITE

func _move_to_road () -> void:
	freeze = true # Rigid bodies don't like being relocated when they're undergoing physics.
	# Temporarily hide other effects like slimed hood.
	$Slimed.hide()
	$Iced.hide()
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "global_position", _pathfollow.global_position, 1.0)
	await tween.finished
	global_rotation = (_pathfollow.global_position - _old_path_pos).angle() - PI/2
	freeze = false
	# Restore other effects.
	$Slimed.show()
	$Iced.show()

func get_slimed (delay: float, full_slime_duration: float, end: float) -> void:
	# Wait a bit for Mango to spit the slime (same timing as screen slime).
	await get_tree().create_timer(delay, false).timeout
	var slime: Sprite2D = $Slimed/Slime
	slime.modulate = Color.hex(0xffffffcc)
	slime.show()
	# Player will already heaar the splat sound from the screen effect, so skip it here.
	if type == CarType.CPU:
		$Slimed/SplatSound.play()
	$Slimed/CPUParticles2D.emitting = true
	effects[EffectType.SLIMED] = true
	var slimefade: Tween = create_tween()
	slimefade.set_ease(Tween.EASE_OUT)
	slimefade.tween_interval(full_slime_duration)
	slimefade.tween_property(slime, "modulate", Color.hex(0xffffff00), end)
	await slimefade.finished
	effects.erase(EffectType.SLIMED)
	slime.hide()

func entered_nailpolish (obj: Node2D, nailpolish_position: Vector2, radius: float, colour: Color) -> void:
	if EffectType.NAILPOLISHED not in effects:
		effects[EffectType.NAILPOLISHED] = {}
	var np: Dictionary = effects[EffectType.NAILPOLISHED]
	np[obj] = [nailpolish_position, radius, colour]

func exited_nailpolish (obj: Node2D) -> void:
	if EffectType.NAILPOLISHED not in effects: return
	effects[EffectType.NAILPOLISHED].erase(obj)

func sip_coffee () -> void:
	$Coffee/SippingSound.play()
	effects[EffectType.CAFFEINATED] = Time.get_ticks_msec()
	$Coffee/CPUParticles2D.emitting = true

func space_rock () -> void:
	#meteor_impact.emit()
	#return
	var shadow: TextureRect = $Meteor/Shadow
	shadow.show()
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	shadow.scale = Vector2(0.1,0.1)
	shadow.position = Vector2(-5,-5)
	shadow.modulate = Color.hex(0x00000000)
	tween.tween_property(shadow, "scale", Vector2(10.0,10.0), 2.0)
	tween.parallel().tween_property(shadow, "position", Vector2(-500,-500),2.0)
	tween.parallel().tween_property(shadow, "modulate", Color.hex(0xffffffaa), 2.0)
	$Meteor/WhooshSound.play()
	await tween.finished
	shadow.hide()
	meteor_impact.emit()
	scream()

func smoulder () -> void:
	effects[EffectType.SMOULDERING] = Time.get_ticks_msec()
	$Meteor/CPUParticles2D.emitting = true

# Try getting a CPU car unstuck from an obstacle.
func _get_unstuck () -> void:
	_getting_unstuck = true
	# Try backing up in one direction.
	cpu_steer_direction = CPU_Steer_Direction.LEFT
	cpu_movement = CPU_Movement.BACKWARD
	await get_tree().create_timer(0.5, false).timeout
	# Now try going forward after turning wheel in other direction.
	cpu_steer_direction = CPU_Steer_Direction.RIGHT
	cpu_movement = CPU_Movement.FORWARD
	await get_tree().create_timer(0.5, false).timeout
	# Hopefully that was enough to get unstuck?
	cpu_steer_direction = CPU_Steer_Direction.PATH
	# Reset the "stuck" state and see if that worked.
	# Otherwise, this routine will get tried again after a brief time.
	_is_stuck = false
	_getting_unstuck = false

func scream() -> void:
	_scream.rpc()
@rpc("authority","call_local","reliable")
func _scream() -> void:
	AHHH.emit()
