extends Node

@export var npc_path: NodePath
@export var api_manager_path: NodePath
@export var npc_id: String = "npc_01"
@export var personality: String = "normal"
@export var update_interval_sec: float = 0.4

@export var env_sound: float = 0.0
@export var env_threat: float = 0.0
@export var env_light: float = 0.0

var _npc: Node
var _api_manager: Node
var _update_timer: Timer

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

	_connect_api_signals()
	_setup_timer()
	_send_init_request()

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
	pass
