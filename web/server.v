module web

import compress.deflate
import compress.gzip
import core
import core.meta
import json
import log
import models
import time
import veb
import venyowong.linq
import x.json2

const compressible_types := [
	'text/plain',
	'text/html',
	'text/css',
	'text/javascript',
	'application/javascript',
	'application/json',
	'application/xml',
	'image/svg+xml',
	'font/woff',
	'font/woff2'
]

pub struct Context {
	veb.Context
}

pub fn (ctx Context) get_param(key string) string {
	mut value := ctx.form[key]
	if value.len > 0 {
		return value
	}

	value = ctx.query[key]
	if value.len > 0 {
		return value
	}

	value = ctx.get_custom_header(key) or {""}
	if value.len > 0 {
		return value
	}

	c := ctx.req.cookie(key) or {
		return ""
	}
	return c.value
}

@[heap]
pub struct App {
	veb.Middleware[Context]
	veb.StaticHandler
	adm_pwd string
	cidrs []CIDR
	jwt_secret string
mut:
	log log.Log
	service &core.Service
}

pub fn App.new(service &core.Service, adm_pwd string, allow_list []string, jwt_secret string) App {
	cidrs := linq.map(allow_list, fn (rule string) CIDR {return CIDR.parse(rule) or {CIDR{}}})
	mut l := log.Log{}
	$if prod {
		l.set_level(.info)
	} $else {
		l.set_level(.debug)
	}
	l.set_full_logpath("./log.txt")
	l.log_to_console_too()
	defer {l.flush()}
	l.info("Talog Http App setup...")

	return App {
		adm_pwd: adm_pwd
		cidrs: cidrs
		jwt_secret: jwt_secret
		log: l
		service: service
	}
}

pub fn (mut app App) check_request_auth(mut ctx Context) bool {
	ip := extract_ipv4_from_mapped(ctx.ip())
	mut b := app.cidrs.include(ip) or {false}
	if b {return true}

	token := ctx.get_param("token")
	b, _ = verify_jwt_token[JwtPayload](app.jwt_secret, token)
	if b {return true}

	ctx.res.set_status(.unauthorized)
	ctx.text("unauthorized")
	return false
}

pub fn (mut app App) compress(mut ctx Context) bool {
	accept_encoding := ctx.req.header.get(.accept_encoding) or { '' }
	content_type := ctx.res.header.get(.content_type) or { '' }
	if ctx.res.body.len >= 512 && is_compressible_content_type(content_type) {
		if accept_encoding.contains("gzip") {
			bytes := gzip.compress(ctx.res.body.bytes()) or {
				app.log.warn("failed to use gzip compress body: ${err.msg()}")
				return true
			}
			ctx.res.header.set(.vary, 'Accept-Encoding')
			ctx.res.header.set(.content_length, bytes.len.str())
			ctx.res.header.set(.content_encoding, "gzip")
			ctx.res.body = bytes.bytestr()
		} else if accept_encoding.contains("deflate") {
			bytes := deflate.compress(ctx.res.body.bytes()) or {
				app.log.warn("failed to use deflate compress body: ${err.msg()}")
				return true
			}
			ctx.res.header.set(.vary, 'Accept-Encoding')
			ctx.res.header.set(.content_length, bytes.len.str())
			ctx.res.header.set(.content_encoding, "deflate")
			ctx.res.body = bytes.bytestr()
		}
	}

	return false
}

pub fn decompress(mut ctx Context) bool {
	content_encoding := ctx.req.header.get(.content_encoding) or { '' }
	if content_encoding.contains("gzip") {
		bytes := gzip.decompress(ctx.req.data.bytes()) or {
			ctx.request_error('invalid gzip encoding')
			return false
		}
		ctx.req.data = bytes.bytestr()
	} else if content_encoding.contains("deflate") {
		bytes := deflate.decompress(ctx.req.data.bytes()) or {
			ctx.request_error('invalid deflate encoding')
			return false
		}
		ctx.req.data = bytes.bytestr()
	}
	return true
}

@["/admin/login"; post]
pub fn (mut app App) login(mut ctx Context) veb.Result {
	hash := md5_hash(app.adm_pwd) or {
		return ctx.json(models.Result.fail(-1, 'exception raised when hashing password: ${err}'))
	}
	data := json2.decode[json2.Any](ctx.req.data) or {
		return ctx.json(models.Result.fail(-1, 'exception raised when parsing json: ${err}'))
	}
	pwd := data.as_map()["pwd"] or {
		return ctx.json(models.Result.fail(-1, 'exception raised when getting pwd from body'))
	}
	if hash != pwd.str() {
		return ctx.json(models.Result.fail(-1, "wrong password"))
	}

	token := make_jwt_token(app.jwt_secret, JwtPayload {
		iat: time.now().unix()
		iss: "talog"
		sub: "admin token"
	})
	return ctx.json(models.Result.success_with(token))
}

@["/index/mappings"; get]
pub fn (mut app App) get_mappings(mut ctx Context) veb.Result {
	mappings := app.service.get_mappings() or {
		return ctx.json(models.Result.fail(-1, "exception raised when getting mappings: $err"))
	}
	return ctx.json(models.Result.success_with(mappings))
}

@["/index"; post]
pub fn (mut app App) index_log(mut ctx Context) veb.Result {
	mut req := json.decode(models.IndexLogReq, ctx.req.data) or {
		return ctx.json(models.Result.fail(-1, "request data is not json"))
	}
	success := app.service.index_log(req.log_type, req.name, req.tags, true, req.log) or {
		return ctx.json(models.Result.fail(-1, "exception raised when indexing log: $err"))
	}
	if success {
		return ctx.json(models.Result{})
	} else {
		return ctx.json(models.Result.fail(-1, "failed to index log"))
	}
}

@["/index/logs"; post]
pub fn (mut app App) index_logs(mut ctx Context) veb.Result {
	defer {app.log.flush()}
	mut r := json.decode(models.IndexLogsReq, ctx.req.data) or {
		return ctx.json(models.Result.fail(-1, "request data is not json"))
	}
	start := time.now().unix_milli()
	app.service.index_logs(r.log_type, r.name, r.tags, r.parse_log, ...r.logs) or {
		return ctx.json(models.Result.fail(-1, "exception raised when indexing logs: $err"))
	}
	elapsed := time.now().unix_milli() - start
	app.log.debug("index $r.name logs, total logs: $r.logs.len, elapsed: $elapsed")
	return ctx.json(models.Result{})
}

@["/index/logs2"; post]
pub fn (mut app App) index_logs2(mut ctx Context) veb.Result {
	defer {app.log.flush()}
	mut reqs := json.decode([]models.IndexLogReq, ctx.req.data) or {
		return ctx.json(models.Result.fail(-1, "request data is not json"))
	}
	start := time.now().unix_milli()
	for mut r in reqs {
		app.service.index_log(r.log_type, r.name, r.tags, true, r.log) or {
			return ctx.json(models.Result.fail(-1, "exception raised when indexing log: $err"))
		}
	}
	elapsed := time.now().unix_milli() - start
	app.log.debug("index multi logs, total logs: $reqs.len, elapsed: $elapsed")
	return ctx.json(models.Result{})
}

@["/index/mapping"; post]
pub fn (mut app App) mapping(mut ctx Context) veb.Result {
	mut m := json.decode(meta.IndexMapping, ctx.req.data) or {
		return ctx.json(models.Result.fail(-1, "request data is not json"))
	}
	c := app.service.check_mapping(m) or {
		return ctx.json(models.Result.fail(-1, "failed to save mappings: $err"))
	}

	if c {
		m.mapping_time = time.now()
		app.service.save_log(m)
		return ctx.json(models.Result{})
	} else {
		return ctx.json(models.Result.fail(-1, "mapping has no change"))
	}
}

@["/search/logs"; get]
pub fn (mut app App) search_logs(mut ctx Context) veb.Result {
	name := ctx.query["name"]
	query := ctx.query["query"]
	log_type := meta.LogType.parse(ctx.query["log_type"]) or {
		return ctx.json(models.Result.fail(-1, "invalid log_type"))
	}
	logs := app.service.search_logs(log_type, name, query) or {
		return ctx.json(models.Result.fail(-1, "exception raised when searching logs: $err"))
	}
	return ctx.send_response_to_client("application/json", json2.encode(models.Result.success_with(logs)))
}

pub fn (mut app App) run_server(port int) ! {
	app.use(handler: decompress)
	app.route_use("/index/:path...", handler: app.check_request_auth)
	app.route_use("/search/:path...", handler: app.check_request_auth)
	app.handle_static("public", true)!
	app.use(handler: app.compress, after: true)
	veb.run[App, Context](mut app, port)
}

fn is_compressible_content_type(content_type string) bool {
    for t in compressible_types {
        if content_type.contains(t) {
            return true
        }
    }
    return false
}