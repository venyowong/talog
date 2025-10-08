module extension

import core
import core.meta
import models
import json
import x.json2

pub fn search_logs(mut service core.Service, log_type meta.LogType, name string, query string) string {
	logs := service.search_logs(log_type, name, query) or {
		return json.encode(models.Result.fail(-1, "exception raised when searching logs: $err"))
	}
	return json2.encode(models.Result.success_with(logs))
}