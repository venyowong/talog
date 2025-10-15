module main

import cli
import core
import extension
import json
import log
import net.http
import os
import rest
import talog
import watch
import zmq

fn main() {
	mut app := cli.Command{
		name:        'v.talog'
		description: 'A local tagging log solution that supports rich communication protocols'
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
				description: 'The path of data, default is ./data/'
				default_value: ['./data/']
			},
			cli.Flag {
				flag: cli.FlagType.string
				abbrev: "h"
				name: 'host'
				description: 'http server host'
				default_value: ['localhost']
			},
			cli.Flag {
				flag: cli.FlagType.int
				abbrev: "p"
				name: 'port'
				description: 'http server port'
				default_value: ['26382']
			},
			cli.Flag {
				flag: cli.FlagType.int
				name: 'zmq_workers'
				description: 'zeromq workers'
				default_value: ['8']
			},
			cli.Flag {
				flag: cli.FlagType.int
				name: 'zmq_port'
				description: 'zeromq host'
				default_value: ['26383']
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

	data_path := cmd.flags.get_string('data')!
	mut service := core.Service {
		data_path: data_path
	}
	service.setup()!
	defer {service.close() or {
		panic("Failed to close service")
	}}
	mut r_service := &service

	l.info("saving mapping...")
	mut config := json.decode(talog.Config, os.read_file(cmd.flags.get_string('config')!)!)!
	for mut m in config.mapping {
		extension.mapping(mut service, mut m)
	}

	mut threads := []thread{}

	host := cmd.flags.get_string("host")!
	port := cmd.flags.get_int("port")!
	mut rest_server := rest.new_server(mut service, host, port)
	mut r_rest_server := &rest_server
	threads << spawn r_rest_server.listen_and_serve()

	threads << spawn watch.watch_by_config(config.watch, mut r_service)

	os.signal_opt(.int, fn [mut service, mut rest_server] (signal os.Signal) {
		elegant_exit(mut service, mut rest_server)
	})!
	os.signal_opt(.term, fn [mut service, mut rest_server] (signal os.Signal) {
		elegant_exit(mut service, mut rest_server)
	})!

	zmq_port := cmd.flags.get_int("zmq_port")!
	spawn zmq.ZmqApp.run(mut r_service, "tcp://$host:$zmq_port", cmd.flags.get_int("zmq_workers")!)

	threads.wait()
}

fn elegant_exit(mut service core.Service, mut rest_server http.Server) {
	service.close() or {
		panic("Failed to close service")
	}
	rest_server.stop()
	exit(0)
}