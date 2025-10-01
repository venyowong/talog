module rest

import core
import veb

pub struct RestApp {
	veb.Controller
pub mut:
	service &core.Service
	index_controller &Index
	search_controller &Search
}

pub struct RestContext {
	veb.Context
}

pub fn (ctx RestContext) get_param(key string) string {
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

pub fn RestApp.new(service &core.Service) RestApp {
	return RestApp {
		service: service
		index_controller: &Index {
			service: service
		}
		search_controller: &Search {
			service: service
		}
	}
}

pub fn (mut app RestApp) run_server(host string, port int) ! {
	app.register_controller[Index, RestContext]('/index', mut app.index_controller)!
	app.register_controller[Search, RestContext]('/search', mut app.search_controller)!
	veb.run_at[RestApp, RestContext](mut app, veb.RunParams {
		host: host
		port: port
	})!
}