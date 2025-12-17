module main

import cli
import core
import json
import log
import os
import web
import talog

fn main() {
	mut app := cli.Command{
		name:        'v.talog'
		description: 'A tiny and simple log solution, talog tag logs to store data in a simple way, so it can be quickly queried'
		execute:     run
		flags: [
			cli.Flag {
				flag: cli.FlagType.string
				abbrev: "c"
				name: 'config'
				description: 'config file, json format'
				default_value: ['./config.json']
			},
			cli.Flag {
				flag: cli.FlagType.string
				name: 'data'
				description: 'The path of data, default value is ./data/'
				default_value: ['./data/']
			},
			cli.Flag {
				flag: cli.FlagType.int
				abbrev: "p"
				name: 'port'
				description: 'http server port, default value is 26382'
				default_value: ['26382']
			}
		]
	}
	app.setup()
	app.parse(os.args)
}

fn run(cmd cli.Command) ! {
	mut l := log.Log{}
	l.set_level(.info)
	l.set_full_logpath("./log.txt")
	l.log_to_console_too()
	l.info("talog is running...")
	log.set_logger(l)
	log.set_always_flush(true)
	mut config := json.decode(talog.Config, os.read_file(cmd.flags.get_string('config')!)!)!

	data_path := cmd.flags.get_string('data')!
	mut service := core.Service {
		data_path: data_path
	}
	service.setup()!

	os.signal_opt(.int, fn [mut service] (signal os.Signal) {
		elegant_exit(mut service)
	})!
	os.signal_opt(.term, fn [mut service] (signal os.Signal) {
		elegant_exit(mut service)
	})!

	port := cmd.flags.get_int("port")!
	mut app := web.App.new(service, config.adm_pwd, config.allow_list, config.jwt_secret)
	app.run_server(port)!
}

fn elegant_exit(mut service core.Service) {
	service.close() or {
		panic("Failed to close service")
	}
	exit(0)
}