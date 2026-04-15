extends CharacterBody3D

signal state_changed(previous_state: String, new_state: String)

@export_enum("Raycast Steering (Matemática Pura)", "Navigation Mesh (A* Nativo de Godot)") var obstacle_avoidance_mode: int = 0

@export var panel_emocional: ColorRect
@export var metrics_label: Label
@export var emoji_label: Label3D
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
	"dormir": true,
	"explore": true,
	"idle": true
}

const DECISION_TO_STATE := {
	"flee": "flee",
	"sleep": "dormir",
	"dormir": "dormir",
	"explore": "explore",
	"idle": "idle"
}

const ATTITUDE_TO_STATE := {
	"panico / supervivencia": "flee",
	"panico": "flee",
	"defensivo / cauteloso": "dormir",
	"defensivo": "dormir",
	"curioso / confiado": "explore",
	"curioso": "explore",
	"neutral / pasivo": "idle",
	"neutral": "idle",
	"sin clasificacion": "idle"
}

const STATE_TO_ANIMATION := {
	"idle": "idle",
	"explore": "walk",
	"flee": "sprint",
	"dormir": "die"
}

const STATE_TO_EMOJI := {
	"idle": "😟",
	"explore": "🌳",
	"flee": "🏃💨",
	"dormir": "😴"
}

const HUD_MARGIN := 16.0
const HUD_GAP := 10.0
const HUD_WIDTH_RATIO := 0.28
const HUD_MIN_WIDTH := 220.0
const HUD_MAX_WIDTH := 360.0
const HUD_PANEL_HEIGHT := 100.0
const HUD_LABEL_HEIGHT_RATIO := 0.45
const HUD_LABEL_MIN_HEIGHT := 120.0
const HUD_LABEL_PADDING := 8.0
const HUD_LABEL_BG_COLOR := Color(0.05, 0.05, 0.05, 0.62)
const HUD_LABEL_TEXT_COLOR := Color(0.78, 0.78, 0.78, 1.0)

var npc_id: String = ""
var personality: String = "normal"
var current_state: String = "idle"
var _animation_player: AnimationPlayer
var _nav_agent: NavigationAgent3D
var _state_anchor: Vector3
var _current_waypoint: Vector3
var _waypoint_timer: float = 0.0
var _state_time: float = 0.0
var _state_forward: Vector3 = Vector3.FORWARD
var _metrics_background: ColorRect

func setup(id_value: String, personality_value: String = "normal") -> void:
	npc_id = id_value
	personality = personality_value

func apply_api_state(data: Dictionary) -> void:
	var next_state := _extract_state_from_response(data)
	if next_state == "":
		# Si la API no manda accion/estado nuevo, se mantiene el estado actual.
		return
	set_state(next_state)

	var decision_text := _extract_text_field(data, "decision")
	var attitude_text := _extract_text_field(data, "attitude")
	var emotion_text := _extract_text_field(data, "emotion")
	var top_emotions_text := _extract_top_emotions_text(data)

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
		# 5. Aplicar animación suave al ColorRect
		if panel_emocional:
			print("Aplicando color: ", color_emocional, " al panel: ", panel_emocional.name)
			var tween = create_tween()
			tween.tween_property(panel_emocional, "color", color_emocional, 0.5)
		else:
			push_warning("NPC %s: panel_emocional no asignado." % npc_id)
			
		# 6. Actualizar Texto de Métricas en el Label
		if metrics_label:
			var stress = float(metrics.get("stress", 0.0))
			var lines: PackedStringArray = [
				"Valence: %.2f" % valence,
				"Arousal: %.2f" % arousal,
				"Stress: %.2f" % stress
			]
			if emotion_text != "":
				lines.append("Emotion: %s" % emotion_text)
			if decision_text != "":
				lines.append("Decision: %s" % decision_text)
			if attitude_text != "":
				lines.append("Attitude: %s" % attitude_text)
			if top_emotions_text != "":
				lines.append("Top: %s" % top_emotions_text)
			metrics_label.text = "\n".join(lines)
			
			# 7. Lógica de Emoji de Pánico (Si el estrés es altísimo, ignoramos el estado)
			if emoji_label:
				if stress > 0.8:
					emoji_label.text = "😨"
				else:
					# Volver al emoji del estado actual si el estrés bajó
					emoji_label.text = STATE_TO_EMOJI.get(current_state, "❓")
		else:
			push_warning("NPC %s: metrics_label no asignado." % npc_id)

	elif metrics_label:
		var fallback_lines: PackedStringArray = []
		if emotion_text != "":
			fallback_lines.append("Emotion: %s" % emotion_text)
		if decision_text != "":
			fallback_lines.append("Decision: %s" % decision_text)
		if attitude_text != "":
			fallback_lines.append("Attitude: %s" % attitude_text)
		if top_emotions_text != "":
			fallback_lines.append("Top: %s" % top_emotions_text)
		if fallback_lines.size() > 0:
			metrics_label.text = "\n".join(fallback_lines)

func set_state(new_state: String) -> void:
	if not VALID_STATES.has(new_state):
		push_warning("NPC %s: estado invalido '%s'." % [npc_id, new_state])
		return

	if current_state == new_state:
		return

	var previous := current_state
	current_state = new_state
	_state_anchor = global_position
	_current_waypoint = _state_anchor
	_waypoint_timer = 0.0
	_state_time = 0.0
	var forward := global_basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		forward = Vector3.BACK
	_state_forward = forward.normalized()
	_play_animation_for_state(current_state)
	
	# Actualizar Emoji de inmediato al cambiar estado
	if emoji_label:
		emoji_label.text = STATE_TO_EMOJI.get(current_state, "❓")
		
	state_changed.emit(previous, current_state)

func _extract_state_from_response(data: Dictionary) -> String:
	if data.has("decision"):
		var decision_state := _map_decision_to_state(str(data["decision"]))
		if decision_state != "":
			return decision_state

	if data.has("attitude"):
		var attitude_state := _map_attitude_to_state(str(data["attitude"]))
		if attitude_state != "":
			return attitude_state

	if data.has("state"):
		var state_mapped := _map_decision_to_state(str(data["state"]))
		if state_mapped != "":
			return state_mapped

	if data.has("action"):
		var action_mapped := _map_decision_to_state(str(data["action"]))
		if action_mapped != "":
			return action_mapped

	return ""

func _normalize_state(raw_value: String) -> String:
	return raw_value.strip_edges().to_lower()

func _normalize_attitude(raw_value: String) -> String:
	return raw_value.strip_edges().to_lower().replace("á", "a").replace("é", "e").replace("í", "i").replace("ó", "o").replace("ú", "u")

func _map_decision_to_state(raw_decision: String) -> String:
	var normalized := _normalize_state(raw_decision)
	if DECISION_TO_STATE.has(normalized):
		return str(DECISION_TO_STATE[normalized])

	if VALID_STATES.has(normalized):
		return normalized

	return ""

func _map_attitude_to_state(raw_attitude: String) -> String:
	var normalized := _normalize_attitude(raw_attitude)
	if ATTITUDE_TO_STATE.has(normalized):
		return str(ATTITUDE_TO_STATE[normalized])
	return ""

func _extract_text_field(data: Dictionary, field_name: String) -> String:
	if not data.has(field_name):
		return ""
	return str(data[field_name]).strip_edges()

func _extract_top_emotions_text(data: Dictionary) -> String:
	if data.has("top_emotions") and data["top_emotions"] is Array:
		var items := data["top_emotions"] as Array
		if items.is_empty():
			return ""
		var values: PackedStringArray = []
		for item in items:
			values.append(str(item))
		return ", ".join(values)

	if data.has("top_options") and data["top_options"] is Array:
		var options := data["top_options"] as Array
		if options.is_empty():
			return ""
		var option_values: PackedStringArray = []
		for option in options:
			option_values.append(str(option))
		return ", ".join(option_values)

	return ""

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
		
	# Instanciamos el Agente de Navegación A* matemáticamente para que no tengas que enlazar nada nuevo en UI
	_nav_agent = NavigationAgent3D.new()
	_nav_agent.path_desired_distance = 0.5
	_nav_agent.target_desired_distance = 0.5
	add_child(_nav_agent)
	
	# --- AUTO-CREACIÓN DE ETIQUETA SI NO EXISTE ---
	if metrics_label == null and panel_emocional != null:
		var new_label = Label.new()
		new_label.name = "DynamicMetricsLabel"
		# Añadirlo al mismo padre que el panel
		panel_emocional.get_parent().add_child(new_label)
		metrics_label = new_label
	
	_configure_hud_layout()
		
	if emoji_label == null:
		var new_emoji = Label3D.new()
		new_emoji.name = "DynamicEmojiLabel"
		new_emoji.position = Vector3(0, 2.2, 0) # Elevado para que no tape la cara
		new_emoji.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		
		# --- MEJORA DE VISIBILIDAD (Calibración Definitiva) ---
		new_emoji.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM # Ancla el emoji por su base
		new_emoji.fixed_size = false      
		new_emoji.pixel_size = 0.012      # Un toque más pequeño que antes para mayor elegancia
		new_emoji.font_size = 120         
		new_emoji.outline_size = 20       
		new_emoji.no_depth_test = true    
		
		new_emoji.text = STATE_TO_EMOJI.get(current_state, "❓")
		add_child(new_emoji)
		emoji_label = new_emoji
		print("✅ Emoji calibrado a escala real sobre el NPC")
	
	_state_anchor = global_position
	_current_waypoint = _state_anchor
	_play_animation_for_state(current_state)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_configure_hud_layout()


func _configure_hud_layout() -> void:
	if panel_emocional == null:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var hud_width := clampf(viewport_size.x * HUD_WIDTH_RATIO, HUD_MIN_WIDTH, HUD_MAX_WIDTH)
	panel_emocional.custom_minimum_size = Vector2(hud_width, HUD_PANEL_HEIGHT)
	panel_emocional.size = Vector2(hud_width, HUD_PANEL_HEIGHT)
	panel_emocional.position = Vector2(viewport_size.x - hud_width - HUD_MARGIN, HUD_MARGIN)

	if metrics_label == null:
		return

	if _metrics_background == null:
		_metrics_background = panel_emocional.get_parent().get_node_or_null("MetricsBackground") as ColorRect
		if _metrics_background == null:
			_metrics_background = ColorRect.new()
			_metrics_background.name = "MetricsBackground"
			_metrics_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_metrics_background.color = HUD_LABEL_BG_COLOR
			_metrics_background.z_index = -1
			panel_emocional.get_parent().add_child(_metrics_background)

	metrics_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	metrics_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	metrics_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	metrics_label.clip_text = true
	metrics_label.add_theme_color_override("font_color", HUD_LABEL_TEXT_COLOR)
	metrics_label.custom_minimum_size = Vector2(hud_width - (HUD_LABEL_PADDING * 2.0), HUD_LABEL_MIN_HEIGHT - (HUD_LABEL_PADDING * 2.0))
	var metrics_bg_size := Vector2(hud_width, maxf(HUD_LABEL_MIN_HEIGHT, viewport_size.y * HUD_LABEL_HEIGHT_RATIO))
	var metrics_bg_pos := panel_emocional.position + Vector2(0.0, panel_emocional.size.y + HUD_GAP)
	_metrics_background.position = metrics_bg_pos
	_metrics_background.size = metrics_bg_size
	metrics_label.position = metrics_bg_pos + Vector2(HUD_LABEL_PADDING, HUD_LABEL_PADDING)
	metrics_label.size = metrics_bg_size - Vector2(HUD_LABEL_PADDING * 2.0, HUD_LABEL_PADDING * 2.0)
	metrics_label.add_theme_font_size_override("font_size", 14)


func _physics_process(delta: float) -> void:
	_state_time += delta
	_waypoint_timer -= delta
	
	var target: Vector3 = _get_target_position_for_state()
	var flat_delta := target - global_position
	flat_delta.y = 0.0

	var desired_velocity := Vector3.ZERO
	if flat_delta.length() > 0.03:
		var desired_speed := _get_move_speed_for_state()
		
		# --- DECISIÓN DEL MOTOR DE INTELIGENCIA FÍSICA ---
		if obstacle_avoidance_mode == 0:
			# -> OPCIÓN 0: RAYCAST STEERING (Evitación Vectorial)
			var raw_dir = flat_delta.normalized()
			var avoid_vector = _calculate_obstacle_avoidance(raw_dir)
			
			# Suaviza el giro combinando el deseo original con la fuerza de repulsión de los troncos
			var final_dir = (raw_dir + (avoid_vector * 2.5)).normalized() # Subimos fuerza de repulsión a 2.5
			desired_velocity = final_dir * desired_speed
			
		elif obstacle_avoidance_mode == 1:
			# -> OPCIÓN 1: NAVIGATION MESH (Algoritmo Clásico A*)
			_nav_agent.target_position = target
			if not _nav_agent.is_navigation_finished():
				var next_point = _nav_agent.get_next_path_position()
				var nav_dir = (next_point - global_position).normalized()
				nav_dir.y = 0.0
				desired_velocity = nav_dir * desired_speed
			else:
				desired_velocity = Vector3.ZERO
			
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
		# Nuevo Sistema: Elegir puntos aleatorios progresivamente (Waypoints) en lugar de dar vueltas tontas
		if global_position.distance_to(_current_waypoint) < 0.8 or _waypoint_timer <= 0.0:
			var rand_angle = randf() * TAU
			# Ignora el "walk radius 0.7" si es muy chico, garantizamos caminatas de 3 a 5 metros
			var dist = randf_range(2.0, maxf(walk_radius, 5.0))
			_current_waypoint = _state_anchor + Vector3(cos(rand_angle), 0.0, sin(rand_angle)) * dist
			_waypoint_timer = randf_range(2.5, 5.0)
			
		return _current_waypoint

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

	# Solo sincronizamos por movimiento los estados que realmente se desplazan.
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

# --- ALGORITMOS DE EVASIÓN MATEMÁTICA ANTE OBSTÁCULOS (Opción 0) ---
func _calculate_obstacle_avoidance(forward_dir: Vector3) -> Vector3:
	var space_state = get_world_3d().direct_space_state
	var avoidance = Vector3.ZERO
	
	var ray_length = 2.0 # Aumentamos alcance visual frontal a 2 metros
	var num_rays = 7     # Lanza 7 rayos sensoriales para más precisión
	var arc_angle = PI / 1.5 # Ampliamos la visión a 120 grados frente a él
	
	var query = PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1 # Choca contra la primera capa de física (donde están tus árboles)
	query.exclude = [self.get_rid()] # Evitar asustarse de su propio cuerpo
	
	for i in range(num_rays):
		# Generar los ángulos de los "bigotes" del gato (-45° a +45°)
		var t = float(i) / float(num_rays - 1) if num_rays > 1 else 0.5
		var angle = lerp(-arc_angle/2.0, arc_angle/2.0, t)
		var dir = forward_dir.rotated(Vector3.UP, angle)
		
		# Proyectar el rayo desde la panza/pecho (altura 0.5) para no estallar con el piso
		var origin = global_position + Vector3(0, 0.5, 0)
		query.from = origin
		query.to = origin + (dir * ray_length)
		
		var result = space_state.intersect_ray(query)
		if result:
			# Si un láser choca contra un tronco, crea una fuerza repulsiva opuesta fuerte
			var distance_factor = 1.0 - (origin.distance_to(result.position) / ray_length)
			avoidance += -dir * distance_factor

	# Normaliza la alerta final para balancear con suavidad el empujón principal del juego
	if avoidance.length() > 0.01:
		avoidance = avoidance.normalized()
		
	return avoidance
