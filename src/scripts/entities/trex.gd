extends CharacterBody3D

@export var walk_speed: float = 3.0
@export var walk_radius: float = 20.0
@export var roar_cooldown_min: float = 8.0
@export var roar_cooldown_max: float = 15.0
@export var roar_duration: float = 3.0 # Cuánto tiempo dura el rugido en segundos

@export_group("Animations")
@export var animation_player_path: NodePath
@export var anim_idle: String = "Idle"
@export var anim_walk: String = "Walk"
@export var anim_roar: String = "Roar"

@export_group("Audio")
@export var audio_roar_path: NodePath

# 🔴 VARIABLE CLAVE: Este es el número que el cerebro del NPC va a vigilar.
var roar_intensity: float = 0.0

var _anchor_pos: Vector3
var _target_pos: Vector3
var _walk_timer: float = 0.0
var _roar_timer: float = 0.0
var _is_roaring: bool = false
var _anim_player: AnimationPlayer
var _audio_roar: AudioStreamPlayer3D

func _ready() -> void:
	_anim_player = get_node_or_null(animation_player_path) as AnimationPlayer
	_audio_roar = get_node_or_null(audio_roar_path) as AudioStreamPlayer3D
	_anchor_pos = global_position
	_target_pos = _anchor_pos
	_pick_new_waypoint()
	_roar_timer = randf_range(roar_cooldown_min, roar_cooldown_max)

func _physics_process(delta: float) -> void:
	_walk_timer -= delta
	
	# 🦖 1. IA DE DEPREDADOR (RUGIDOS AUTÓNOMOS)
	if not _is_roaring:
		_roar_timer -= delta
		if _roar_timer <= 0.0:
			_start_roar()
	else:
		# Durante el rugido, la bestia se queda quieta y emite un pulso de ruido brutal.
		_roar_timer -= delta
		
		# Curva de rugido: Se mantiene en 1.0 durante la mayor parte y cae rápido al final
		# (Si el timer esta arriba del 20% del total, la escala es 1.0)
		roar_intensity = clamp(_roar_timer / (roar_duration * 0.8), 0.0, 1.0)
		
		if _roar_timer <= 0.0:
			_is_roaring = false
			roar_intensity = 0.0
			_roar_timer = randf_range(roar_cooldown_min, roar_cooldown_max)
			_pick_new_waypoint() # Reanuda el merodeo
			
	# 🐾 2. SISTEMA DE PATRULLAJE TERRESTRE
	if not _is_roaring:
		# Si llegó a su destino o se frustró buscando, elige otro lugar
		if global_position.distance_to(_target_pos) < 1.0 or _walk_timer <= 0.0:
			_pick_new_waypoint()
			
		var flat_delta = _target_pos - global_position
		flat_delta.y = 0.0
		
		if flat_delta.length() > 0.1:
			var raw_dir = flat_delta.normalized()
			
			# -- EVASIÓN DE OBSTÁCULOS (Árboles y Rocas) --
			var avoid_vector = _calculate_obstacle_avoidance(raw_dir)
			
			# Fuerza masiva repulsiva (3.0) porque es de cuerpo enorme
			var final_dir = (raw_dir + (avoid_vector * 3.0)).normalized()
			
			velocity.x = move_toward(velocity.x, final_dir.x * walk_speed, 10.0 * delta)
			velocity.z = move_toward(velocity.z, final_dir.z * walk_speed, 10.0 * delta)
			
			# Orientación basada en su ruta final y no en el delta ciego
			# Restamos el vector en lugar de sumarlo para acoplar el eje +Z (Rotación del modelo de Blender original)
			if velocity.length_squared() > 0.01:
				var look_target = global_position - velocity.normalized()
				var target_transform = global_transform.looking_at(look_target, Vector3.UP)
				global_transform.basis = global_transform.basis.slerp(target_transform.basis, delta * 5.0)
			
		else:
			velocity = Vector3.ZERO
			
	# Físicas bases (Gravedad y Muro)
	if not is_on_floor():
		velocity.y -= 9.8 * delta
		
	move_and_slide()
	_sync_animations()

func _sync_animations() -> void:
	if _anim_player == null:
		return
		
	var target_anim = anim_idle
	if _is_roaring:
		target_anim = anim_roar
	elif velocity.length() > 0.1:
		target_anim = anim_walk
		
	# Si la animación existe y no se está reproduciendo ya, la iniciamos
	if _anim_player.has_animation(target_anim):
		if _anim_player.current_animation != target_anim:
			_anim_player.play(target_anim, 0.3)
	elif target_anim != anim_idle and _anim_player.has_animation(anim_idle):
		if _anim_player.current_animation != anim_idle:
			_anim_player.play(anim_idle, 0.3)

func _pick_new_waypoint() -> void:
	var rand_angle = randf() * TAU
	var dist = randf_range(5.0, walk_radius)
	_target_pos = _anchor_pos + Vector3(cos(rand_angle), 0.0, sin(rand_angle)) * dist
	_walk_timer = randf_range(8.0, 15.0)

func _start_roar() -> void:
	_is_roaring = true
	_roar_timer = roar_duration # Usa la duración personalizable
	roar_intensity = 1.0 # Al máximo nivel enviando estrés al sistema
	velocity = Vector3.ZERO # El T-Rex frena para rugir
	
	if _audio_roar != null:
		_audio_roar.play()
		
	print("🦖 ¡RRRWAAAAAAAAAAAR! (Pulso Sonoro Emitido Globalmente)")

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
