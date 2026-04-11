extends Node

signal request_completed(endpoint: String, data: Dictionary)
signal request_failed(endpoint: String, status_code: int, message: String)

@onready var http := HTTPRequest.new()

var BASE_URL := "http://127.0.0.1:8000"
var _pending_endpoint: String = ""

func _ready():
	add_child(http)
	http.request_completed.connect(_on_request_completed)

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
	if http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		push_warning("API busy. Espera a que termine la request actual.")
		return

	var json := JSON.stringify(payload)
	var headers := ["Content-Type: application/json"]
	_pending_endpoint = endpoint

	var err = http.request(
		BASE_URL + endpoint,
		headers,
		HTTPClient.METHOD_POST,
		json
	)

	if err != OK:
		_pending_endpoint = ""
		push_error("Error enviando request: %s" % str(err))
		request_failed.emit(endpoint, -1, "No se pudo enviar la request")

func _on_request_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
	var text := body.get_string_from_utf8()
	var endpoint := _pending_endpoint
	_pending_endpoint = ""
	
	if code < 200 or code >= 300:
		var error_message := _extract_error_message(text)
		push_error("API ERROR %s en %s: %s" % [str(code), endpoint, error_message])
		request_failed.emit(endpoint, code, error_message)
		return
	
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		request_failed.emit(endpoint, code, "Respuesta JSON invalida")
		push_error("Respuesta JSON invalida en %s" % endpoint)
		return
	
	request_completed.emit(endpoint, parsed)

func _extract_error_message(text: String) -> String:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		var data: Dictionary = parsed
		if data.has("detail"):
			return str(data["detail"])
	return text
