class_name InteractionDetector
extends Node
## Attached to the LOCAL player. Picks the best interactable in front of the player
## (distance + view direction), exposes a prompt, and triggers it on the interact key.

signal prompt_changed(text: String)

var player: Player
var target: Interactable = null
var _prompt := ""


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	var best: Interactable = null
	if player.seated:
		best = player.current_seat
	elif player.input_enabled and not player.is_locked():
		best = _find_best()
	target = best
	var text := ""
	if best != null:
		text = best.get_prompt(player)
	if text != _prompt:
		_prompt = text
		prompt_changed.emit(text)


func _find_best() -> Interactable:
	var fwd := player.get_look_forward()
	var best: Interactable = null
	var best_score := INF
	for n in get_tree().get_nodes_in_group("interactable"):
		var it := n as Interactable
		if it == null or not it.can_interact(player):
			continue
		var to := it.interaction_point() - player.global_position
		to.y = 0.0
		var d := to.length()
		if d > it.max_distance:
			continue
		var facing := fwd.dot(to.normalized()) if d > 0.001 else 1.0
		if facing < 0.2 and d > 1.0:
			continue
		var score := d - facing * 0.8
		if score < best_score:
			best_score = score
			best = it
	return best


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.input_enabled or not event.is_action_pressed("interact"):
		return
	if player.seated:
		player.stand()
	elif target != null and target.can_interact(player):
		target.interact(player)
