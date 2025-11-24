extends Node2D


func _on_area_2d_body_entered(_body: Node2D) -> void:
	if multiplayer.get_unique_id() != 1: return
	$AudioStreamPlayer2D.play()
	$TrainSignal1.play('on')
	$TrainSignal2.play('on')

func _on_area_2d_body_exited(_body: Node2D) -> void:
	if multiplayer.get_unique_id() != 1: return
	$AudioStreamPlayer2D.stop()
	$TrainSignal1.animation = 'off'
	$TrainSignal1.stop()
	$TrainSignal2.animation = 'off'
	$TrainSignal2.stop()
