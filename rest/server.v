module rest

import core
import core.meta
import extension
import json
import models
import net.http
import net.urllib

pub struct HttpHandler {
pub mut:
	service &core.Service
}

pub fn (mut h HttpHandler) handle(req http.Request) http.Response {
	mut res := http.Response {
		header: req.header
	}
	strs := req.url.split("?")
	path := strs[0]
	mut query_string := ""
	if strs.len > 1 {
		query_string = strs[1]
	}
	if path.ends_with("/index/mappings") {
		res.body = extension.get_mappings(mut h.service)
	} else if path.ends_with("/index") {
		mut r := json.decode(models.IndexLogReq, req.data) or {
			res.set_status(.bad_request)
			res.body = "request data is not json"
			return res
		}
		res.body = extension.index_log(mut h.service, r)
	} else if path.ends_with("/index/mapping") {
		mut m := json.decode(meta.IndexMapping, req.data) or {
			res.set_status(.bad_request)
			res.body = "request data is not json"
			return res
		}
		res.body = extension.mapping(mut h.service, mut m)
	} else if path.ends_with("/search") {
		q := urllib.parse_query(query_string) or {
			res.set_status(.bad_request)
			res.body = "invalid url query string"
			return res
		}
		name := q.get("name") or {
			res.set_status(.bad_request)
			res.body = "name can't be empty"
			return res
		}
		query := q.get("query") or {""}
		log_type := meta.LogType.parse(q.get("log_type") or {
			res.set_status(.bad_request)
			res.body = "log_type can't be empty"
			return res
		}) or {
			res.set_status(.bad_request)
			res.body = "invalid log_type"
			return res
		}
		res.body = extension.search_logs(mut h.service, log_type, name, query)
	}
	res.header.set_custom("Content-Type", "application/json") or {
		panic("failed to set custom header")
	}
	res.set_status(.ok)
	res.set_version(req.version)
	return res
}

pub fn new_server(mut service core.Service, host string, port int) http.Server {
	h := HttpHandler {
		service: service
	}
	return http.Server {
		handler: h
		addr: "$host:$port"
	}
}