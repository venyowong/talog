module rest

import core
import core.meta
import json
import models
import time
import veb

pub struct Index{
pub mut:
	service &core.Service
}

@["/mappings"; get]
pub fn (mut index Index) get_mappings(mut ctx RestContext) veb.Result {
	mappings := index.service.get_mappings() or {
		return ctx.json(models.Result.fail(-1, "exception raised when getting mappings: $err"))
	}
	return ctx.json(models.Result.success_with(mappings))
}

@["/"; post]
pub fn (mut index Index) index_log(mut ctx RestContext) veb.Result {
	mut req := json.decode(models.IndexLogReq, ctx.req.data) or {
		return ctx.json(models.Result.fail(-1, "request data is not json"))
	}
	success := index.service.index_log(req.log_type, req.name, req.tags, req.log) or {
		return ctx.json(models.Result.fail(-1, "exception raised when indexing log: $err"))
	}
	if success {
		return ctx.json(models.Result{})
	} else {
		return ctx.json(models.Result.fail(-1, "failed to index log"))
	}
}

@[post]
pub fn (mut index Index) mapping(mut ctx RestContext) veb.Result {
	mut m := json.decode(meta.IndexMapping, ctx.req.data) or {
		return ctx.json(models.Result.fail(-1, "request data is not json"))
	}
	c := index.service.check_mapping(m) or {
		return ctx.json(models.Result.fail(-1, "failed to save mappings: $err"))
	}

	if c {
		m.mapping_time = time.now()
		index.service.save_log(m) or {
			return ctx.json(models.Result.fail(-1, "exception raised when saving mappings: $err"))
		}
		return ctx.json(models.Result{})
	} else {
		return ctx.json(models.Result.fail(-1, "mapping has no change"))
	}
}