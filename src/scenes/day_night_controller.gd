extends Node

@export var sun: DirectionalLight3D
@export var moon: DirectionalLight3D
@export var world_env: WorldEnvironment

var time_of_day := 0.5
var day_duration := 20.0
var env: Environment

# DEBUG
var debug_timer := 0.0
var debug_interval := 1.0

func _ready():
	if world_env == null:
		push_error("WorldEnvironment no asignado")
		return
	
	env = world_env.environment
	if env == null:
		push_error("WorldEnvironment sin Environment")
		return

func _process(delta):
	time_of_day += delta / day_duration
	time_of_day = fmod(time_of_day, 1.0)
	
	_update_lighting()
	
	# DEBUG
	debug_timer += delta
	if debug_timer >= debug_interval:
		debug_timer = 0.0
		#_print_debug()

# 🔥 BASE CORRECTA (FIX PRINCIPAL)
func _get_height():
	return sin((time_of_day - 0.25) * TAU)

func _get_angle():
	return (time_of_day - 0.25) * TAU

# 🔥 SISTEMA UNIFICADO
func _update_lighting():
	var angle = _get_angle()
	var height = _get_height()
	
	_update_sun(angle, height)
	_update_moon(angle, height)
	_update_environment(height)

# ☀️ SOL
func _update_sun(angle, height):
	if sun == null:
		return
	
	# 1. ALTURA DEL SOL (BASE DEL SISTEMA)
	
	# 2. ROTACIÓN
	sun.rotation_degrees.x = rad_to_deg(angle)
	
	# 3. INTENSIDAD (AQUÍ AJUSTAS CUÁNDO EMPIEZA EL DÍA)
	var intensity = smoothstep(-0.3, 0.6, height)
	sun.light_energy = intensity * 1.2  # 🔧 potencia máxima
	
	# 4. COLOR (TRANSICIÓN SIMPLE)
	var night_color = Color(0.2, 0.25, 0.4)
	var day_color = Color(1.0, 0.96, 0.9)
	
	var day_factor = smoothstep(-0.4, 0.5, height)
	sun.light_color = night_color.lerp(day_color, day_factor)
	
	# 5. SOMBRAS
	sun.shadow_enabled = intensity > 0.05
	#if sun == null:
		#return
	#
	#sun.rotation_degrees.x = rad_to_deg(angle)
	#
	#var intensity = smoothstep(-0.05, 0.5, height)
	#intensity = max(intensity, 0.03)
	#
	#sun.light_energy = intensity * 1.2
	#
	#var sunset = Color(1.0, 0.5, 0.3)
	#var day = Color(1.0, 0.96, 0.9)
	#var night = Color(0.1, 0.12, 0.2)
	#
	#var sunset_factor = smoothstep(-0.1, 0.2, height) * (1.0 - smoothstep(0.2, 0.6, height))
	#var day_factor = smoothstep(0.2, 0.8, height)
	#
	#var color = night
	#color = color.lerp(sunset, sunset_factor)
	#color = color.lerp(day, day_factor)
	#
	#sun.light_color = color
	#
	#sun.shadow_enabled = intensity > 0.05
	#sun.shadow_opacity = clamp(intensity, 0.2, 1.0)

# 🌙 LUNA
# 🌙 LUNA
func _update_moon(angle, height):
	if moon == null:
		return
	
	# 🌙 POSICIÓN OPUESTA (ángulo + 180 grados)
	moon.rotation_degrees.x = rad_to_deg(angle + PI)
	
	# 🌗 ALTURA - Calcular intensidad basada en altura de la luna
	var moon_intensity = clamp((height + 0.2) / 0.8, 0.0, 1.0)
	
	# 💡 LUZ - Bastante más brillante para noche visible
	moon.light_energy = moon_intensity * 1.2  # Aumentado a 1.2
	
	# 🎨 COLOR LUNA - Más blanco para mejor iluminación
	var base_color = Color(0.7, 0.75, 1.0)
	var strong_color = Color(0.9, 0.92, 1.0)
	
	moon.light_color = base_color.lerp(strong_color, moon_intensity)
	
	# 🌑 SOMBRAS
	moon.shadow_enabled = moon_intensity > 0.1
	if moon.shadow_enabled:
		moon.shadow_normal_bias = 0.35
		moon.shadow_blur = 1.2

# 🌍 AMBIENTE - CORREGIDO PARA NOCHE VISIBLE
func _update_environment(height):
	if env == null:
		return
	
	# Factor día (0 = noche, 1 = día)
	var day_factor = smoothstep(-0.3, 0.5, height)
	
	# 📸 EXPOSURE - Valores más altos para noche
	var night_exposure = 0.45  # Aumentado de 0.3 a 0.45
	var day_exposure = 0.65   # Aumentado de 0.6 a 0.65
	
	env.tonemap_exposure = lerp(night_exposure, day_exposure, day_factor)
	
	# 🌈 LUZ AMBIENTAL - CLAVE PARA VER EN NOCHE
	var night_ambient_color = Color(0.15, 0.18, 0.28)  # Más claro
	var day_ambient_color = Color(0.7, 0.75, 0.85)
	
	var night_ambient_energy = 0.55  # Aumentado de 0.35 a 0.55
	var day_ambient_energy = 0.75    # Aumentado de 0.7 a 0.75
	
	env.ambient_light_color = night_ambient_color.lerp(day_ambient_color, day_factor)
	env.ambient_light_energy = lerp(night_ambient_energy, day_ambient_energy, day_factor)
	
	# 🌫️ NIEBLA - Menos densa en noche para mejor visibilidad
	env.fog_enabled = true
	
	var fog_night_color = Color(0.12, 0.14, 0.22)  # Más claro
	var fog_day_color = Color(0.75, 0.8, 0.9)
	
	env.fog_light_color = fog_night_color.lerp(fog_day_color, day_factor)
	env.fog_density = lerp(0.008, 0.003, day_factor)  # Menos niebla

# VERSIÓN ALTERNATIVA - Si la noche sigue oscura, usa valores fijos:
func _update_environment_alternativo(height):
	if env == null:
		return
	
	var day_factor = smoothstep(-0.3, 0.5, height)
	
	# Valores más agresivos para noche
	if day_factor < 0.3:  # Es noche
		env.tonemap_exposure = 0.55
		env.ambient_light_energy = 0.65
		env.ambient_light_color = Color(0.18, 0.2, 0.32)
		env.fog_density = 0.005
		env.fog_light_color = Color(0.15, 0.17, 0.25)
	elif day_factor > 0.7:  # Es día
		env.tonemap_exposure = 0.7
		env.ambient_light_energy = 0.8
		env.ambient_light_color = Color(0.7, 0.75, 0.85)
		env.fog_density = 0.002
		env.fog_light_color = Color(0.75, 0.8, 0.9)
	else:  # Transición
		var t = (day_factor - 0.3) / 0.4
		env.tonemap_exposure = lerp(0.55, 0.7, t)
		env.ambient_light_energy = lerp(0.65, 0.8, t)
		env.ambient_light_color = Color(0.18, 0.2, 0.32).lerp(Color(0.7, 0.75, 0.85), t)
		env.fog_density = lerp(0.005, 0.002, t)
		env.fog_light_color = Color(0.15, 0.17, 0.25).lerp(Color(0.75, 0.8, 0.9), t)

# 🧪 DEBUG
func _print_debug():
	var height = _get_height()
	var day_factor = smoothstep(-0.1, 0.4, height)
	
	print(
		"Hora:", get_time_string(),
		" | TOD:", snapped(time_of_day, 0.001),
		" | Height:", snapped(height, 0.001),
		" | DayFactor:", snapped(day_factor, 0.001)
	)

# UTILIDADES
func set_time_of_day(value: float):
	time_of_day = clamp(value, 0.0, 1.0)

func get_time_string() -> String:
	var total_hours = time_of_day * 24.0
	var hours = int(total_hours)
	var minutes = int((total_hours - hours) * 60)
	return "%02d:%02d" % [hours, minutes]

func is_daytime() -> bool:
	return _get_height() > 0.0
