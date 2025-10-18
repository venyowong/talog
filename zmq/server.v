module zmq

import core
import core.meta
import extension
import json
import log
import models
import venyowong.vmq
import x.json2

pub struct Req {
pub mut:
	action string
	data json2.Any
}

pub struct ZmqApp {
mut:
	backend vmq.Socket
	closed bool
	ctx vmq.Context
	frontend vmq.Socket
	log log.Log
pub mut:
	service &core.Service
}

pub fn ZmqApp.run(mut service core.Service, addr string, workers int) &ZmqApp {
	mut l := log.Log{}
	l.set_level(.info)
	l.set_full_logpath("./log.txt")
	l.log_to_console_too()
	l.info("ZmqApp setup...")
	mut ctx := vmq.new_context()
	mut frontend := vmq.new_socket(ctx, vmq.SocketType.router) or {
		panic("failed to create frontend socket: $err")
	}
	frontend.bind(addr) or {
		panic("failed to bind frontend socket to $addr: $err")
	}
	l.info("zmq frontend socket is binding on $addr")
	mut backend := vmq.new_socket(ctx, vmq.SocketType.dealer) or {
		panic("failed to create backend socket: $err")
	}
	inproc_addr := "inproc://workers"
	backend.bind(inproc_addr) or {
		panic("failed to bind backend socket to $inproc_addr: $err")
	}
	l.info("zmq backend socket is binding on $inproc_addr")
	mut app := &ZmqApp {
		ctx: ctx
		frontend: frontend
		backend: backend
		service: service
		log: l
	}

	for i := 0; i < workers; i++ {
		spawn fn [inproc_addr, mut app] (ctx &vmq.Context) {
			worker := vmq.new_socket(ctx, vmq.SocketType.rep) or {
				app.log.error("failed to create worker socket: $err")
				return
			}
			worker.connect(inproc_addr) or {
				app.log.error("worker socket cannot connect to $inproc_addr: $err")
				return
			}
			for {
				if app.closed {return}

				msg := worker.recv() or {
					app.log.warn("exception raised when rep socket worker receiving msg: $err")
					continue
				}
				j := msg.bytestr()
				req := json2.decode[Req](j) or {
					app.log.warn("the msg is not json which rep socket worder received: $j")
					continue
				}
				worker.send((app.handle_req(req) or {
					app.log.warn("exception raised when rep socket worker handling msg: $err")
					continue
				}).bytes()) or {
					app.log.warn("exception raised when rep socket worker sending msg: $err")
					continue
				}
			}
		}(ctx)
	}
	
	return app
}

pub fn (mut app ZmqApp) close() {
	app.log.info("ZmqApp is closing...")
	app.closed = true
	app.frontend.free()
	app.backend.free()
	app.ctx.free()
}

pub fn (mut app ZmqApp) proxy() {
	vmq.proxy(app.frontend, app.backend) or {
		app.log.error("zmq proxy error: $err")
	}
}

fn (mut app ZmqApp) handle_req(req Req) !string {
	action := req.action.to_lower()
	if action == "get_mappings" {
		return extension.get_mappings(mut app.service)
	}
	if action == "index_log" {
		return extension.index_log(mut app.service, json.decode(models.IndexLogReq, json2.encode(req.data))!)
	}
	if action == "mapping" {
		mut m := json.decode(meta.IndexMapping, json2.encode(req.data))!
		return extension.mapping(mut app.service, mut m)
	}
	if action == "search_logs" {
		m := req.data as map[string]json2.Any
		log_type := m["log_type"]!.str()
		return extension.search_logs(mut app.service, meta.LogType.parse(log_type) or {
			return json.encode(models.Result.fail(-1, "invalid log_type: $log_type"))
		}, m["name"]!.str(), m["query"]!.str())
	}
	return error("unsupported action")
}