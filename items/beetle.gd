extends Area2D

var target: Node2D = null
var velocity: Vector2 = Vector2.ZERO
@export var acceleration: float = 1000.0
@export var dampen: float = 1000.0
@export var max_speed: float = 2000.0
@export var min_impulse: float = 500.0
var active: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func set_target (car: Node2D) -> void:
	target = car
	$BuzzSound.play(1.0)
	# Wait a bit before becoming active
	# (so we don't hit the car that just launched us).
	await get_tree().create_timer(1.0, false).timeout
	active = true
	# Need to start animation via RPC, because it's not clear what property
	# to put into a MultiplayerSynchronizer to achieve the same effect.
	_start_animation.rpc()
@rpc("authority","reliable","call_local")
func _start_animation() -> void:
	$AnimatedSprite2D.play()

# When no target available, just fly away.
func buzz_off () -> void:
	global_rotation = velocity.angle() - PI/2
	set_target($FlyAway)
	# Remove from scene after some fixed amount of time.
	await get_tree().create_timer(10.0, false).timeout
	queue_free()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if target == null: return
	var direction: Vector2 = target.global_position - global_position
	global_rotation = direction.angle() - PI/2
	var new_velocity: Vector2 = velocity + delta*acceleration*direction.normalized()# - delta*dampen*velocity.normalized()
	# Limit amount of strafing around the target.
	var strafing_direction: Vector2 = Vector2.from_angle(global_rotation)
	var strafing_speed: float = new_velocity.dot(strafing_direction)
	if strafing_speed > delta*dampen:
		new_velocity -= delta*dampen*strafing_direction
	elif strafing_speed < -delta*dampen:
		new_velocity += delta*dampen*strafing_direction
	new_velocity = new_velocity.limit_length(max_speed)
	velocity = new_velocity
	global_position += velocity * delta


func _on_body_entered(body: Node2D) -> void:
	if not active: return
	if "_crash_effect" in body:
		if "apply_impulse" in body:
			var dv: Vector2 = velocity - body.linear_velocity
			if dv.length() < min_impulse:
				dv = dv.normalized()*min_impulse
			body.apply_impulse(dv)
		if "apply_torque_impulse" in body:
			body.apply_torque_impulse(20000)
		if "scream" in body:
			body.scream()
		body._crash_effect()
		active = false
		target = $FlyAway
		var tween: Tween = create_tween()
		tween.tween_property(self, "modulate", Color.hex(0xffffff00), 1.0)
		tween.parallel().tween_property($BuzzSound, "volume_db", -10, 1.0)
		await tween.finished
		queue_free()
