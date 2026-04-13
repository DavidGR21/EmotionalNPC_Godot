extends Node

@export var npc_path: NodePath
@export var api_manager_path: NodePath
@export var npc_id: String = "npc_01"
@export var personality: String = "cobarde"
@export var update_interval_sec: float = 0.4
@export var perception_label: Label

@export_group("World Perception")
@export var player_path: NodePath
@export var day_night_controller_path: NodePath

@export var env_sound: float = 0.0
@export var env_threat: float = 0.0
@export var env_light: float = 0.0

var _npc: Node
var _api_manager: Node
var _update_timer: Timer
var _player: Node3D
var _day_night: Node

func _ready() -> void:
	_npc = get_node_or_null(npc_path)
	_api_manager = get_node_or_null(api_manager_path)

	if _npc == null:
		push_error("NpmController: npc_path no configurado o invalido.")
		return

	if _api_manager == null:
		push_error("NpmController: api_manager_path no configurado o invalido.")
		return

	if _npc.has_method("setup"):
		_npc.call("setup", npc_id, personality)

	if player_path:
		_player = get_node_or_null(player_path)
	if day_night_controller_path:
		_day_night = get_node_or_null(day_night_controller_path)

	_connect_api_signals()
	_setup_timer()
	_send_init_request()
	
	# --- AUTO-CREACIÓN DE ETIQUETA DE PERCEPCIÓN ---
	if perception_label == null:
		var canvas = get_tree().root.find_child("CanvasLayer", true, false)
		if canvas:
			var new_label = Label.new()
			new_label.name = "PerceptionLabel"
			# Lo ponemos un poco más abajo del panel emocional (suponiendo que está en el mismo Canvas)
			new_label.position = Vector2(20, 250) # Coordenada fija segura o relativa si tuviéramos referencia
			canvas.add_child(new_label)
			perception_label = new_label

func _connect_api_signals() -> void:
	if not _api_manager.request_completed.is_connected(_on_api_request_completed):
		_api_manager.request_completed.connect(_on_api_request_completed)

	if _api_manager.has_signal("request_failed"):
		if not _api_manager.request_failed.is_connected(_on_api_request_failed):
			_api_manager.request_failed.connect(_on_api_request_failed)

func _setup_timer() -> void:
	_update_timer = Timer.new()
	_update_timer.one_shot = false
	_update_timer.wait_time = maxf(update_interval_sec, 0.05)
	_update_timer.timeout.connect(_on_update_timeout)
	add_child(_update_timer)

func set_environment(sound: float, threat: float, light: float) -> void:
	env_sound = sound
	env_threat = threat
	env_light = light

func request_update() -> void:
	if _api_manager == null:
		return
	_api_manager.call("update_npc", npc_id, env_sound, env_threat, env_light)

func _send_init_request() -> void:
	_api_manager.call("init_npc", npc_id, personality)

func _on_update_timeout() -> void:
	request_update()

func _on_api_request_completed(endpoint: String, data: Dictionary) -> void:
	if endpoint == "/npc/init":
		if not _update_timer.is_stopped():
			return
		_update_timer.start()
		request_update()
		return

	if endpoint == "/npc/%s/update" % npc_id:
		var api_action := _extract_api_action(data)
		print("NPC %s - accion API: %s" % [npc_id, api_action])
		if _npc.has_method("apply_api_state"):
			_npc.call("apply_api_state", data)

func _extract_api_action(data: Dictionary) -> String:
	if data.has("action"):
		return str(data["action"])

	if data.has("state"):
		return str(data["state"])

	if data.has("decision"):
		return str(data["decision"])

	return "<sin accion>"

func _on_api_request_failed(endpoint: String, status_code: int, message: String) -> void:
	push_warning("API request fallo en %s (%s): %s" % [endpoint, str(status_code), message])
	if endpoint == "/npc/init" and _update_timer != null:
		_update_timer.stop()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if _npc == null: return
	
	# 1. Calcular Luz dinámica basada en el ciclo día/noche
	if _day_night != null and _day_night.has_method("_get_height"):
		var sun_height = _day_night.call("_get_height")
		# Mapear la altura del sol (-1 a 1) a nivel de luz (0 a 1)
		env_light = clamp((sun_height + 0.3) / 0.8, 0.0, 1.0)
	else:
		# Si no hay nodo de día/noche vinculado, simulamos un ciclo de luz lento para pruebas
		var t_light = float(Time.get_ticks_msec()) / 1000.0
		# Ciclo súper lento (emula horas del día)
		env_light = (sin(t_light * 0.1) + 1.0) * 0.5 
		
	# 2. Calcular Amenaza y Sonido respecto al Jugador
	if _player != null and _player != _npc:
		# Lógica real (Se activará automáticamente cuando asignes a tu Player real)
		var distance = _npc.global_position.distance_to(_player.global_position)
		
		# AMENAZA: Aumenta si el jugador está muuy cerca (<= 2m la amenaza es 1.0, >= 8m la amenaza es 0)
		env_threat = clamp(1.0 - ((distance - 1.5) / 6.5), 0.0, 1.0)
		
		# SONIDO: Mezcla los pasos del jugador con los RUGIDOS del T-Rex
		var roar_noise = 0.0
		if "roar_intensity" in _player:
			roar_noise = _player.roar_intensity
		
		if "velocity" in _player:
			var player_speed = _player.velocity.length()
			var speed_factor = clamp(player_speed / 5.0, 0.0, 1.0) # 5.0 es la velocidad normal
			
			# Atenuación auditiva (pasos amortiguados por distancia)
			var atten = clamp(1.0 - (distance / 12.0), 0.0, 1.0)
			
			# El rugido (roar_noise) no usa 'atten' para que retumbe mecánicamente en toda la isla entera.
			env_sound = max(speed_factor * atten, roar_noise)
		else:
			# Si es un objeto extraño que no camina, solo escucha su rugido de forma global.
			env_sound = roar_noise
	else:
		# SIMULACIÓN DE PRUEBA (Se ejecuta mientras el Player esté vacío)
		# Variamos los datos progresivamente usando ondas en base al reloj para inyectar "eventos" imaginarios
		var t = float(Time.get_ticks_msec()) / 1000.0
		
		var wave_threat = (sin(t * 0.3) + 1.0) * 0.5 # Ciclo largo de ~20 segs
		var wave_sound = (cos(t * 0.7 + 2.0) + 1.0) * 0.5 # Ciclo irregular
		
		# Aplicamos picos intensos en vez de ruido constante para que la IA tenga descanso
		env_threat = clamp((wave_threat * 1.5) - 0.7, 0.0, 1.0) 
		env_sound = clamp((wave_sound * 1.8) - 1.0, 0.0, 1.0)
		
	# 3. Actualizar Interfaz en tiempo real
	if perception_label:
		perception_label.text = "--- PERCEPCIÓN NPC ---\nSonido: %.2f\nAmenaza: %.2f\nLuz: %.2f" % [env_sound, env_threat, env_light]
