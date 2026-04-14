extends CharacterBody3D

@export var walk_speed: float = 3.0
@export var run_speed: float = 6.0
@export var walk_radius: float = 20.0
@export var roar_cooldown_min: float = 8.0
@export var roar_cooldown_max: float = 15.0
@export var roar_duration: float = 3.0 # Cuánto tiempo dura el rugido en segundos
@export var roar_fade_out_time: float = 2.2 # Tiempo para que la señal de rugido baje a 0
@export var roar_fade_in_speed: float = 10.0 # Velocidad de subida hacia intensidad máxima

@export_group("Control")
@export var player_control_enabled: bool = true
@export var move_left_action: StringName = "ui_left"
@export var move_right_action: StringName = "ui_right"
@export var move_forward_action: StringName = "ui_up"
@export var move_back_action: StringName = "ui_down"
@export var run_key: Key = KEY_SHIFT
@export var roar_key: Key = KEY_F

@export_group("Animations")
@export var animation_player_path: NodePath
@export var anim_idle: String = "Armature|TRex_Idle"
@export var anim_walk: String = "Armature|TRex_Walk"
@export var anim_run: String = "Armature|TRex_Run"
@export var anim_roar: String = "Roar"
@export var roar_hold_time: float = 0.28

@export_group("Audio")
@export var audio_roar_path: NodePath

# 🔴 VARIABLE CLAVE: Este es el número que el cerebro del NPC va a vigilar.
var roar_intensity: float = 0.0

var _anchor_pos: Vector3
var _target_pos: Vector3
var _walk_timer: float = 0.0
var _roar_timer: float = 0.0
var _is_roaring: bool = false
var _is_running: bool = false
var _roar_target_intensity: float = 0.0
var _roar_animation_locked: bool = false
var _anim_player: AnimationPlayer
var _audio_roar: AudioStreamPlayer3D

func _ready() -> void:
	_anim_player = get_node_or_null(animation_player_path) as AnimationPlayer
	_audio_roar = get_node_or_null(audio_roar_path) as AudioStreamPlayer3D
	_anchor_pos = global_position
	_target_pos = _anchor_pos
	if not player_control_enabled:
		_pick_new_waypoint()
		_roar_timer = randf_range(roar_cooldown_min, roar_cooldown_max)

func _physics_process(delta: float) -> void:
	if _is_roaring:
		if player_control_enabled:
			_update_player_roar_state()
		else:
			_update_ai_roar_state(delta)
	else:
		if player_control_enabled:
			_process_player_movement(delta)
		else:
			_process_ai_behavior(delta)
			
	# Físicas bases (Gravedad y Muro)
	if not is_on_floor():
		velocity.y -= 9.8 * delta
		
	move_and_slide()
	_update_roar_intensity(delta)
	_sync_animations()

func _sync_animations() -> void:
	if _anim_player == null:
		return

	# Flujo manual del rugido: primero corre hasta roar_hold_time y luego se congela ahi.
	if _is_roaring and player_control_enabled and _anim_player.has_animation(anim_roar):
		_sync_player_roar_animation()
		return

	_anim_player.speed_scale = 1.0
		
	var target_anim = anim_idle
	if _is_roaring:
		target_anim = anim_roar
	elif _is_running and velocity.length() > 0.1:
		target_anim = anim_run
	elif velocity.length() > 0.1:
		target_anim = anim_walk
		
	# Si la animación existe y no se está reproduciendo ya, la iniciamos
	if _anim_player.has_animation(target_anim):
		if _anim_player.current_animation != target_anim:
			_anim_player.play(target_anim, 0.3)
	elif target_anim != anim_idle and _anim_player.has_animation(anim_idle):
		if _anim_player.current_animation != anim_idle:
			_anim_player.play(anim_idle, 0.3)

func _sync_player_roar_animation() -> void:
	if _anim_player.current_animation != anim_roar:
		_anim_player.speed_scale = 1.0
		_anim_player.play(anim_roar, 0.2)
		_roar_animation_locked = false
		return

	if _roar_animation_locked:
		_anim_player.seek(roar_hold_time, true)
		_anim_player.speed_scale = 0.0
		return

	_anim_player.speed_scale = 1.0
	if _anim_player.current_animation_position >= roar_hold_time:
		_anim_player.seek(roar_hold_time, true)
		_anim_player.speed_scale = 0.0
		_roar_animation_locked = true

func _process_player_movement(delta: float) -> void:
	_is_running = false
	if Input.is_key_pressed(roar_key):
		_start_roar()
		return

	var input_dir = Input.get_vector(move_left_action, move_right_action, move_forward_action, move_back_action)
	var world_dir = Vector3(input_dir.x, 0.0, input_dir.y)

	if world_dir.length() > 0.1:
		var raw_dir = world_dir.normalized()
		var avoid_vector = _calculate_obstacle_avoidance(raw_dir)
		var final_dir = (raw_dir + (avoid_vector * 3.0)).normalized()

		_is_running = Input.is_key_pressed(run_key)
		var target_speed = run_speed if _is_running else walk_speed
		velocity.x = move_toward(velocity.x, final_dir.x * target_speed, 10.0 * delta)
		velocity.z = move_toward(velocity.z, final_dir.z * target_speed, 10.0 * delta)

		var look_target = global_position - final_dir
		var target_transform = global_transform.looking_at(look_target, Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(target_transform.basis, delta * 8.0)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)

func _update_player_roar_state() -> void:
	# En control manual el rugido se mantiene solo mientras la tecla esté presionada.
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * get_physics_process_delta_time())
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * get_physics_process_delta_time())
	_is_running = false

	if Input.is_key_pressed(roar_key):
		_roar_target_intensity = 1.0
	else:
		_stop_roar()

func _process_ai_behavior(delta: float) -> void:
	_walk_timer -= delta

	# IA de depredador (rugidos autónomos)
	_roar_timer -= delta
	if _roar_timer <= 0.0:
		_start_roar()
		return

	# Sistema de patrullaje terrestre
	if global_position.distance_to(_target_pos) < 1.0 or _walk_timer <= 0.0:
		_pick_new_waypoint()

	var flat_delta = _target_pos - global_position
	flat_delta.y = 0.0

	if flat_delta.length() > 0.1:
		var raw_dir = flat_delta.normalized()
		var avoid_vector = _calculate_obstacle_avoidance(raw_dir)
		var final_dir = (raw_dir + (avoid_vector * 3.0)).normalized()

		velocity.x = move_toward(velocity.x, final_dir.x * walk_speed, 10.0 * delta)
		velocity.z = move_toward(velocity.z, final_dir.z * walk_speed, 10.0 * delta)
		_is_running = false

		if velocity.length_squared() > 0.01:
			var look_target = global_position - velocity.normalized()
			var target_transform = global_transform.looking_at(look_target, Vector3.UP)
			global_transform.basis = global_transform.basis.slerp(target_transform.basis, delta * 5.0)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		_is_running = false

func _update_ai_roar_state(delta: float) -> void:
	# Durante el rugido, la bestia se queda quieta y emite un pulso de ruido brutal.
	_roar_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)

	# Mantener intensidad objetivo estable durante el rugido.
	_roar_target_intensity = 1.0

	if _roar_timer <= 0.0:
		_stop_roar()

func _pick_new_waypoint() -> void:
	var rand_angle = randf() * TAU
	var dist = randf_range(5.0, walk_radius)
	_target_pos = _anchor_pos + Vector3(cos(rand_angle), 0.0, sin(rand_angle)) * dist
	_walk_timer = randf_range(8.0, 15.0)

func _start_roar() -> void:
	if _is_roaring:
		return

	_is_roaring = true
	_roar_animation_locked = false
	if not player_control_enabled:
		_roar_timer = roar_duration # Usa la duración personalizable en IA
	_roar_target_intensity = 1.0 # Al máximo nivel enviando estrés al sistema
	_is_running = false
	velocity.x = 0.0
	velocity.z = 0.0 # El T-Rex frena para rugir
	
	if _audio_roar != null and not _audio_roar.playing:
		_audio_roar.play()
		
	print("🦖 ¡RRRWAAAAAAAAAAAR! (Pulso Sonoro Emitido Globalmente)")

func _stop_roar() -> void:
	if not _is_roaring:
		return

	_is_roaring = false
	_roar_animation_locked = false
	_roar_target_intensity = 0.0
	_is_running = false
	if _anim_player != null:
		_anim_player.speed_scale = 1.0

	if _audio_roar != null and _audio_roar.playing:
		_audio_roar.stop()

	if not player_control_enabled:
		_roar_timer = randf_range(roar_cooldown_min, roar_cooldown_max)
		_pick_new_waypoint() # Reanuda el merodeo

func _update_roar_intensity(delta: float) -> void:
	var safe_fade_time = max(roar_fade_out_time, 0.01)
	var fade_out_speed = 1.0 / safe_fade_time
	var speed = roar_fade_in_speed if _roar_target_intensity > roar_intensity else fade_out_speed
	roar_intensity = move_toward(roar_intensity, _roar_target_intensity, speed * delta)

# --- SISTEMA SENSORIAL DEL T-REX ---
func _calculate_obstacle_avoidance(forward_dir: Vector3) -> Vector3:
	var space_state = get_world_3d().direct_space_state
	var avoidance = Vector3.ZERO
	
	var ray_length = 3.5 # Vista frontal estirada a 3 metros (El TRex es muy largo)
	var num_rays = 7     
	var arc_angle = PI / 1.5 # 120 Grados de visión periférica
	
	var query = PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1 
	query.exclude = [self.get_rid()] 
	
	for i in range(num_rays):
		var t = float(i) / float(num_rays - 1) if num_rays > 1 else 0.5
		var angle = lerp(-arc_angle/2.0, arc_angle/2.0, t)
		var dir = forward_dir.rotated(Vector3.UP, angle)
		
		# Proyectar desde el cuello/cabeza (1.5 m)
		var origin = global_position + Vector3(0, 1.5, 0) 
		query.from = origin
		query.to = origin + (dir * ray_length)
		
		var result = space_state.intersect_ray(query)
		if result:
			var distance_factor = 1.0 - (origin.distance_to(result.position) / ray_length)
			avoidance += -dir * distance_factor

	if avoidance.length() > 0.01:
		avoidance = avoidance.normalized()
		
	return avoidance
