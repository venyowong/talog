module web

import core
import core.meta
import extension
import json
import models
import net.http
import net.urllib
import os
import time
import venyowong.linq
import x.json2

pub struct HttpHandler {
mut:
	cidrs []CIDR
pub:
	adm_pwd string
	allow_list []string
	jwt_secret string
pub mut:
	service &core.Service
}

pub fn (mut h HttpHandler) handle(req http.Request) http.Response {
	if h.cidrs.len != h.allow_list.len {
		h.cidrs = linq.map(h.allow_list, fn (rule string) CIDR {return CIDR.parse(rule) or {CIDR{}}})
	}
	url := urllib.parse(req.url) or {
		return create_response(req, .internal_server_error, 
			'exception raised when parsing url: ${err}', "text/plain")
	}
	if url.path.starts_with("/admin/") {
		return h.handle_admin(req, url)
	} else if url.path.starts_with("/index/") {
		return h.handle_index(req, url)
	} else if url.path.starts_with("/search/") {
		return h.handle_search(req, url)
	} else {
		return h.handle_static(req, url)
	}
}

fn (h HttpHandler) check_request_auth(req http.Request) bool {
	ip := get_real_client_ip(req)
	mut b := h.cidrs.include(ip) or {false}
	if b {return true}

	token := req.header.get_custom("token") or {""}
	b, _ = verify_jwt_token[JwtPayload](h.jwt_secret, token)
	return b
}

fn create_response(req http.Request, status http.Status, body string, content_type string) http.Response {
	mut res := http.Response{}
	res.header.set(.content_type, content_type)
	res.set_status(status)
	res.set_version(req.version)
	res.body = body
	res.header.set(.content_length, body.len.str())
	return res
}

fn create_bytes_response(req http.Request, status http.Status, body []u8, content_type string) http.Response {
	mut res := http.Response{}
	res.header.set(.content_type, content_type)
	res.set_status(status)
	res.set_version(req.version)
	res.body = body.bytestr()
	res.header.set(.content_length, body.len.str())
	return res
}

fn get_mime_type(file_path string) string {
    ext := os.file_ext(file_path).to_lower()
    match ext {
        '.html', '.htm' { return 'text/html' }
        '.css' { return 'text/css' }
        '.js' { return 'text/javascript' }
        '.json' { return 'application/json' }
        '.png' { return 'image/png' }
        '.jpg', '.jpeg' { return 'image/jpeg' }
        '.gif' { return 'image/gif' }
        '.svg' { return 'image/svg+xml' }
        '.ico' { return 'image/x-icon' }
        '.txt' { return 'text/plain' }
        else { return 'application/octet-stream' }
    }
}

fn (mut h HttpHandler) handle_admin(req http.Request, url urllib.URL) http.Response {
	if url.path == "/admin/login" {
		hash := md5_hash(h.adm_pwd) or {
			return create_response(req, .internal_server_error, 
				'exception raised when hashing password: ${err}', "text/plain")
		}
		data := json2.decode[json2.Any](req.data) or {
			return create_response(req, .internal_server_error, 
				'exception raised when parsing json: ${err}', "text/plain")
		}
		pwd := data.as_map()["pwd"] or {
			return create_response(req, .internal_server_error, 
				'exception raised when getting pwd from body', "text/plain")
		}
		if hash != pwd.str() {
			return create_response(req, .unauthorized, "wrong password", "text/plain")
		}

		token := make_jwt_token(h.jwt_secret, JwtPayload {
			iat: time.now().unix()
			iss: "talog"
			sub: "admin token"
		})
		return create_response(req, .ok, json.encode(models.Result.success_with(token)), "application/json")
	}

	return create_response(req, .not_found, "", "")
}

fn (mut h HttpHandler) handle_index(req http.Request, url urllib.URL) http.Response {
	if !h.check_request_auth(req) {
		return create_response(req, .unauthorized, "", "")
	}
	if url.path.starts_with("/index/mappings") {
		return create_response(req, .ok, extension.get_mappings(mut h.service), "application/json")
	} else if url.path == "/index/log" {
		mut r := json.decode(models.IndexLogReq, req.data) or {
			return create_response(req, .bad_request, "request data is not json", "text/plain")
		}
		return create_response(req, .ok, extension.index_log(mut h.service, r), "application/json")
	} else if url.path == "/index/logs" {
		mut r := json.decode(models.IndexLogsReq, req.data) or {
			return create_response(req, .bad_request, "request data is not json", "text/plain")
		}
		return create_response(req, .ok, extension.index_logs(mut h.service, r), "application/json")
	} else if url.path == "/index/mapping" {
		mut m := json.decode(meta.IndexMapping, req.data) or {
			return create_response(req, .bad_request, "request data is not json", "text/plain")
		}
		return create_response(req, .ok, extension.mapping(mut h.service, mut m), "application/json")
	}

	return create_response(req, .not_found, "", "")
}

fn (mut h HttpHandler) handle_search(req http.Request, url urllib.URL) http.Response {
	if !h.check_request_auth(req) {
		return create_response(req, .unauthorized, "", "")
	}
	if url.path.starts_with("/search/logs") {
		q := urllib.parse_query(url.raw_query) or {
			return create_response(req, .bad_request, "invalid url query string", "text/plain")
		}
		name := q.get("name") or {
			return create_response(req, .bad_request, "name can't be empty", "text/plain")
		}
		query := q.get("query") or {""}
		log_type := meta.LogType.parse(q.get("log_type") or {
			return create_response(req, .bad_request, "log_type can't be empty", "text/plain")
		}) or {
			return create_response(req, .bad_request, "invalid log_type", "text/plain")
		}
		return create_response(req, .ok, extension.search_logs(mut h.service, log_type, name, query), "application/json")
	}
	
	return create_response(req, .not_found, "", "")
}

fn (h HttpHandler) handle_static(req http.Request, url urllib.URL) http.Response {
	file_path := os.join_path("./public", url.path)
	if !os.exists(file_path) || os.is_dir(file_path) {
		return create_response(req, .not_found, "", "")
	}

	bytes := os.read_bytes(file_path) or {
		return create_response(req, .bad_request, 'Error reading file: ${err}', "text/plain")
	}

	return create_bytes_response(req, .ok, bytes, get_mime_type(file_path))
}