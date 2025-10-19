module extension

import core
import core.meta
import models
import json
import time

pub fn get_mappings(mut service core.Service) string {
	mappings := service.get_mappings() or {
		return json.encode(models.Result.fail(-1, "exception raised when getting mappings: $err"))
	}
	return json.encode(models.Result.success_with(mappings))
}

pub fn index_log(mut service core.Service, req models.IndexLogReq) string {
	success := service.index_log(req.log_type, req.name, req.tags, req.log) or {
		return json.encode(models.Result.fail(-1, "exception raised when indexing log: $err"))
	}
	if success {
		return json.encode(models.Result{})
	} else {
		return json.encode(models.Result.fail(-1, "failed to index log"))
	}
}

pub fn index_logs(mut service core.Service, req models.IndexLogsReq) string {
	service.index_logs(req.log_type, req.name, req.tags, ...req.logs) or {
		return json.encode(models.Result.fail(-1, "exception raised when indexing log: $err"))
	}
	return json.encode(models.Result{})
}

pub fn mapping(mut service core.Service, mut req meta.IndexMapping) string {
	c := service.check_mapping(req) or {
		return json.encode(models.Result.fail(-1, "failed to save mappings: $err"))
	}

	if c {
		req.mapping_time = time.now()
		service.save_log(req) or {
			return json.encode(models.Result.fail(-1, "exception raised when saving mappings: $err"))
		}
		return json.encode(models.Result{})
	} else {
		return json.encode(models.Result.fail(-1, "mapping has no change"))
	}
}