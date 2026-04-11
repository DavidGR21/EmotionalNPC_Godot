extends CharacterBody3D

const SPEED = 5.0
const GRAVITY = 9.8
const ROTATION_SPEED = 10.0

@export var anim: AnimationPlayer
@export var model: Node3D

func _ready():
	# Verificar escalas al iniciar
	_check_scales()

func _check_scales():
	# Verificar escala del CharacterBody3D
	if scale != Vector3.ONE:
		print("ERROR: CharacterBody3D tiene escala ", scale, " - Debe ser (1,1,1)")
		scale = Vector3.ONE
	
	# Verificar escala del modelo
	if model and model.scale != Vector3.ONE:
		print("ERROR: Model tiene escala ", model.scale, " - Debe ser (1,1,1)")
		print("Corrigiendo escala del modelo...")
		model.scale = Vector3.ONE

func _physics_process(delta):
	if not anim or not model:
		return
	
	# Asegurar que el CharacterBody3D nunca tenga escala no uniforme
	if scale != Vector3.ONE:
		scale = Vector3.ONE
	
	# gravedad
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0

	# movimiento
	var dir = Vector3.ZERO

	if Input.is_action_pressed("ui_right"):
		dir.x += 1
	if Input.is_action_pressed("ui_left"):
		dir.x -= 1
	if Input.is_action_pressed("ui_up"):
		dir.z -= 1
	if Input.is_action_pressed("ui_down"):
		dir.z += 1

	dir = dir.normalized()

	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED

	# ANIMACIONES Y ROTACIÓN
	if dir != Vector3.ZERO:
		var target_angle = atan2(dir.x, dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_angle, ROTATION_SPEED * delta)
		play_anim("walk")
	else:
		play_anim("idle")

	move_and_slide()

func play_anim(name):
	if anim and anim.current_animation != name:
		anim.play(name)
