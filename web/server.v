module web

import core
import veb

pub struct App {
pub mut:
	service &core.Service
}

pub struct Context {
	veb.Context
}

pub fn run_server(port int) {
	mut app := &App{
	}
	veb.run[App, Context](mut app, port)
}