extends RefCounted
## Only the standard ranking contract is implemented by this blank template.

func check_request(request: Dictionary) -> Dictionary:
	if request.get("mode") != "standard":
		return {"ok": false, "code": "unsupported_mode", "message": "本游戏仅支持 standard 普通局"}
	return {"ok": true}

func make_config(request: Dictionary) -> Dictionary:
	return request.duplicate(true)

func map_result(result: Dictionary, _request: Dictionary) -> Dictionary:
	return result.duplicate(true)
