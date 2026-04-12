extends CharacterBody3D

signal state_changed(previous_state: String, new_state: String)

@export var panel_emocional: ColorRect
@export var animation_player_path: NodePath
@export var animation_blend_sec: float = 0.2
@export var walk_radius: float = 0.7
@export var walk_speed: float = 1.5
@export var sprint_distance: float = 1.8
@export var sprint_speed: float = 4.0
@export var walk_cycle_speed: float = 1.0
@export var sprint_cycle_speed: float = 2.6
@export var move_acceleration: float = 10.0
@export var stop_acceleration: float = 14.0

const VALID_STATES := {
	"flee": true,
	"hide": true,
	"observe": true,
	"explore": true,
	"idle": true
}

const STATE_TO_ANIMATION := {
	"idle": "idle",
	"explore": "walk",
	"observe": "static",
	"flee": "sprint",
	"hide": "die"
}

var npc_id: String = ""
var personality: String = "normal"
var current_state: String = "idle"
var _animation_player: AnimationPlayer
var _state_anchor: Vector3
var _state_time: float = 0.0
var _state_forward: Vector3 = Vector3.FORWARD

func setup(id_value: String, personality_value: String = "normal") -> void:
	npc_id = id_value
	personality = personality_value

func apply_api_state(data: Dictionary) -> void:
	var next_state := _extract_state_from_response(data)
	if next_state == "":
		# Si la API no manda accion/estado nuevo, se mantiene el estado actual.
		return
	set_state(next_state)

	# --- NUEVA LÓGICA DE COLOR (Espectro Emocional) ---
	print("Data in apply_api_state: ", data)
	if data.has("metrics"):
		var metrics = data["metrics"]
		var valence = float(metrics.get("valence", 0.5))
		var arousal = float(metrics.get("arousal", 0.5))
		print("Valence: ", valence, ", Arousal: ", arousal)
		
		# 1. Mapeamos Valence a Hue (Tono). De rojo a cian.
		var hue = lerp(0.0, 0.5, valence) 
		
		# 2. Mapeamos Arousal a Brillo. Oscuro a iluminado.
		var brightness = lerp(0.2, 1.0, arousal) 
		
		# 3. Construimos el color
		var color_emocional = Color.from_hsv(hue, 0.9, brightness)
		
		# 4. Modificamos color drástico en estado de huir
		if current_state == "flee":
			color_emocional = Color.RED
			
		# 5. Aplicar animación suave
		if panel_emocional:
			print("Aplicando color: ", color_emocional, " al panel: ", panel_emocional.name)
			var tween = create_tween()
			tween.tween_property(panel_emocional, "color", color_emocional, 0.5)
		else:
			push_error("Error: panel_emocional es NULL. No se asignó el nodo en el inspector.")
func set_state(new_state: String) -> void:
	if not VALID_STATES.has(new_state):
		push_warning("NPC %s: estado invalido '%s'." % [npc_id, new_state])
		return

	if current_state == new_state:
		return

	var previous := current_state
	current_state = new_state
	_state_anchor = global_position
	_state_time = 0.0
	var forward := global_basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		forward = Vector3.BACK
	_state_forward = forward.normalized()
	_play_animation_for_state(current_state)
	state_changed.emit(previous, current_state)

func _extract_state_from_response(data: Dictionary) -> String:
	if data.has("state"):
		return _normalize_state(str(data["state"]))

	if data.has("action"):
		return _normalize_state(str(data["action"]))

	if data.has("decision"):
		return _normalize_state(str(data["decision"]))

	return ""

func _normalize_state(raw_value: String) -> String:
	return raw_value.strip_edges().to_lower()

func _play_animation_for_state(state: String) -> void:
	if _animation_player == null:
		return

	var animation_name: String = str(STATE_TO_ANIMATION.get(state, ""))
	if animation_name == "":
		return

	if not _animation_player.has_animation(animation_name):
		push_warning("NPC %s: no existe animacion '%s'." % [npc_id, animation_name])
		return

	if _animation_player.current_animation == animation_name and _animation_player.is_playing():
		return

	_animation_player.play(animation_name, animation_blend_sec)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if animation_player_path != NodePath("") and _animation_player == null:
		push_warning("NPC %s: animation_player_path invalido." % npc_id)
	_state_anchor = global_position
	_play_animation_for_state(current_state)


func _physics_process(delta: float) -> void:
	_state_time += delta
	var target: Vector3 = _get_target_position_for_state()
	var flat_delta := target - global_position
	flat_delta.y = 0.0

	var desired_velocity := Vector3.ZERO
	if flat_delta.length() > 0.03:
		var desired_speed := _get_move_speed_for_state()
		desired_velocity = flat_delta.normalized() * desired_speed

	_sync_movement_animation(desired_velocity)

	var accel := stop_acceleration
	if desired_velocity.length() > 0.0:
		accel = move_acceleration

	velocity.x = move_toward(velocity.x, desired_velocity.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired_velocity.z, accel * delta)
	velocity.y = 0.0
	move_and_slide()

	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if flat_velocity.length() > 0.05:
		look_at(global_position - flat_velocity.normalized(), Vector3.UP)


func _get_target_position_for_state() -> Vector3:
	if current_state == "explore":
		var angle := _state_time * walk_cycle_speed
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * walk_radius
		return _state_anchor + offset

	if current_state == "flee":
		var wave := sin(_state_time * sprint_cycle_speed)
		return _state_anchor + (_state_forward * wave * sprint_distance)

	return _state_anchor


func _get_move_speed_for_state() -> float:
	if current_state == "explore":
		return maxf(walk_speed, 0.1)

	if current_state == "flee":
		return maxf(sprint_speed, 0.1)

	return 0.0


func _sync_movement_animation(desired_velocity: Vector3) -> void:
	if _animation_player == null:
		return

	if current_state != "explore" and current_state != "flee":
		return

	if desired_velocity.length() < 0.03:
		return

	var expected_animation: String = str(STATE_TO_ANIMATION.get(current_state, ""))
	if expected_animation == "":
		return

	if not _animation_player.has_animation(expected_animation):
		return

	if _animation_player.current_animation != expected_animation or not _animation_player.is_playing():
		_animation_player.play(expected_animation, animation_blend_sec)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
