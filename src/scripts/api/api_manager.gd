extends Node

signal request_completed(endpoint: String, data: Dictionary)
signal request_failed(endpoint: String, status_code: int, message: String)

var BASE_URL := "http://127.0.0.1:8000"
var _host: String = "127.0.0.1"
var _port: int = 8000
var _use_tls: bool = false

var _client := HTTPClient.new()
var _request_queue: Array[Dictionary] = []
var _active_request: Dictionary = {}
var _active_response_body: PackedByteArray = PackedByteArray()
var _active_status_code: int = -1
var _active_has_response: bool = false

func _ready():
	_parse_base_url()
	_open_connection()

func _process(_delta: float) -> void:
	_poll_client()
	_process_request_queue()

func init_npc(npc_id: String, personality: String = "normal"):
	post("/npc/init", {
		"id": npc_id,
		"personality": personality
	})

func update_npc(npc_id: String, sound: float, threat: float, light: float):
	post("/npc/%s/update" % npc_id, {
		"sound": sound,
		"threat": threat,
		"light": light
	})

func post(endpoint: String, payload: Dictionary):
	var request := {
		"endpoint": endpoint,
		"payload": payload.duplicate(true)
	}

	# Para updates, conservar solo el ultimo valor pendiente y evitar saturacion.
	if endpoint.ends_with("/update"):
		for i in range(_request_queue.size() - 1, -1, -1):
			if _request_queue[i].get("endpoint", "") == endpoint:
				_request_queue.remove_at(i)

	_request_queue.append(request)

func _parse_base_url() -> void:
	var clean_url := BASE_URL.strip_edges()
	_use_tls = clean_url.begins_with("https://")

	if _use_tls:
		clean_url = clean_url.trim_prefix("https://")
	else:
		clean_url = clean_url.trim_prefix("http://")

	var slash_idx := clean_url.find("/")
	if slash_idx >= 0:
		clean_url = clean_url.substr(0, slash_idx)

	var colon_idx := clean_url.rfind(":")
	if colon_idx > 0:
		_host = clean_url.substr(0, colon_idx)
		_port = int(clean_url.substr(colon_idx + 1))
	else:
		_host = clean_url
		_port = 443 if _use_tls else 80

func _open_connection() -> void:
	if _client.get_status() != HTTPClient.STATUS_DISCONNECTED:
		return

	var tls_options: TLSOptions = TLSOptions.client() if _use_tls else null
	var err := _client.connect_to_host(_host, _port, tls_options)
	if err != OK:
		push_error("No se pudo conectar al backend: %s" % str(err))

func _poll_client() -> void:
	var status := _client.get_status()
	if status == HTTPClient.STATUS_DISCONNECTED:
		_open_connection()
		return

	if status in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_REQUESTING, HTTPClient.STATUS_BODY, HTTPClient.STATUS_CONNECTED]:
		var err := _client.poll()
		if err != OK:
			_fail_active_request(-1, "Error al hacer poll del cliente HTTP")
			_reset_connection()
			return

	_process_active_response()

func _process_request_queue() -> void:
	if _active_request.size() > 0:
		return

	if _request_queue.is_empty():
		return

	if _client.get_status() != HTTPClient.STATUS_CONNECTED:
		return

	_active_request = _request_queue.pop_front()
	_active_response_body = PackedByteArray()
	_active_status_code = -1
	_active_has_response = false

	var endpoint: String = _active_request.get("endpoint", "")
	var payload: Dictionary = _active_request.get("payload", {})
	var body := JSON.stringify(payload)
	var headers := [
		"Host: %s" % _host,
		"Content-Type: application/json",
		"Connection: keep-alive"
	]

	var err := _client.request(HTTPClient.METHOD_POST, endpoint, headers, body)
	if err != OK:
		_fail_active_request(-1, "No se pudo enviar la request")
		_reset_connection()

func _process_active_response() -> void:
	if _active_request.is_empty():
		return

	if not _active_has_response and _client.has_response():
		_active_has_response = true
		_active_status_code = _client.get_response_code()

	if _client.get_status() == HTTPClient.STATUS_BODY:
		var chunk := _client.read_response_body_chunk()
		if not chunk.is_empty():
			_active_response_body.append_array(chunk)
		return

	if _active_has_response and _client.get_status() == HTTPClient.STATUS_CONNECTED:
		_finish_active_request()
		return

	if _client.get_status() in [HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
		_fail_active_request(-1, "Conexion HTTP perdida")
		_reset_connection()

func _finish_active_request() -> void:
	var endpoint: String = _active_request.get("endpoint", "")
	var text := _active_response_body.get_string_from_utf8()

	if _active_status_code < 200 or _active_status_code >= 300:
		var error_message := _extract_error_message(text)
		push_error("API ERROR %s en %s: %s" % [str(_active_status_code), endpoint, error_message])
		request_failed.emit(endpoint, _active_status_code, error_message)
		_clear_active_request()
		return

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		request_failed.emit(endpoint, _active_status_code, "Respuesta JSON invalida")
		push_error("Respuesta JSON invalida en %s" % endpoint)
		_clear_active_request()
		return

	request_completed.emit(endpoint, parsed)
	_clear_active_request()

func _fail_active_request(status_code: int, message: String) -> void:
	if _active_request.is_empty():
		return
	var endpoint: String = _active_request.get("endpoint", "")
	request_failed.emit(endpoint, status_code, message)
	_clear_active_request()

func _clear_active_request() -> void:
	_active_request.clear()
	_active_response_body = PackedByteArray()
	_active_status_code = -1
	_active_has_response = false

func _reset_connection() -> void:
	_client.close()
	_open_connection()

func _extract_error_message(text: String) -> String:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		var data: Dictionary = parsed
		if data.has("detail"):
			return str(data["detail"])
	return text
