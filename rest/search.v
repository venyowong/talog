module rest

import core
import core.meta
import models
import veb
import x.json2

pub struct Search{
pub mut:
	service &core.Service
}

@["/"; get]
pub fn (mut search Search) search_logs(mut ctx RestContext) veb.Result {
	name := ctx.get_param("name")
	if name.len <= 0 {
		return ctx.json(models.Result.fail(-1, "name can't be empty"))
	}

	query := ctx.get_param("query")
	log_type := meta.LogType.parse(ctx.get_param("log_type")) or {
		return ctx.json(models.Result.fail(-1, "invalid log_type"))
	}
	logs := search.service.search_logs(log_type, name, query) or {
		return ctx.json(models.Result.fail(-1, "exception raised when searching logs: $err"))
	}
	return ctx.send_response_to_client("application/json", json2.encode(models.Result.success_with(logs)))
}