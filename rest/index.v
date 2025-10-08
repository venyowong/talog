module rest

import core
import core.meta
import extension
import json
import models
import veb

pub struct Index{
pub mut:
	service &core.Service
}

@["/mappings"; get]
pub fn (mut index Index) get_mappings(mut ctx RestContext) veb.Result {
	result := extension.get_mappings(mut index.service)
	return ctx.send_response_to_client("application/json", result)
}

@["/"; post]
pub fn (mut index Index) index_log(mut ctx RestContext) veb.Result {
	mut req := json.decode(models.IndexLogReq, ctx.req.data) or {
		return ctx.json(models.Result.fail(-1, "request data is not json"))
	}
	result := extension.index_log(mut index.service, req)
	return ctx.send_response_to_client("application/json", result)
}

@[post]
pub fn (mut index Index) mapping(mut ctx RestContext) veb.Result {
	mut m := json.decode(meta.IndexMapping, ctx.req.data) or {
		return ctx.json(models.Result.fail(-1, "request data is not json"))
	}
	result := extension.mapping(mut index.service, mut m)
	return ctx.send_response_to_client("application/json", result)
}