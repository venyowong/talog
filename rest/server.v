module rest

import veb
import core

pub struct RestApp {
pub mut:
	service &core.Service
}

pub struct RestContext {
	veb.Context
}

pub fn (mut app RestApp) run_server(port int) {
	veb.run[RestApp, RestContext](mut app, port)
}