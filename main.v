module main

import cli
import core
import core.meta
import json
import log
import net.http
import os
import web
import talog
import time
import watch

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
				flag: cli.FlagType.string
				abbrev: "h"
				name: 'host'
				description: 'http server host, default value is localhost',
				default_value: ['localhost']
			},
			cli.Flag {
				flag: cli.FlagType.string
				abbrev: "m"
				name: 'mode'
				description: 'talog run mode: watch/server/all'
				required: true
				default_value: ['all']
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
	mut config := json.decode(talog.Config, os.read_file(cmd.flags.get_string('config')!)!)!
	mut mode := cmd.flags.get_string("mode")!
	mode = mode.to_lower()
	mut threads := []thread{}

	if mode == "watch" {
		mut indexer := watch.Indexer {
			host: config.server
		}
		mut r_indexer := &indexer
		threads << spawn watch.watch_by_config(config.watch, mut r_indexer)
	} else {
		data_path := cmd.flags.get_string('data')!
		mut service := core.Service {
			data_path: data_path
		}
		service.setup()!
		l.info("saving mapping...")
		for mut m in config.mapping {
			mapping(mut service, mut m)!
		}

		host := cmd.flags.get_string("host")!
		port := cmd.flags.get_int("port")!
		mut handler := web.HttpHandler {
			adm_pwd: config.adm_pwd
			allow_list: config.allow_list
			jwt_secret: config.jwt_secret
			service: &service
		}
		mut rest_server := http.Server {
			handler: handler
			addr: "$host:$port"
		}
		mut r_rest_server := &rest_server
		threads << spawn r_rest_server.listen_and_serve()

		if mode == "all" {
			mut indexer := watch.Indexer {
				service: service
			}
			mut r_indexer := &indexer
			threads << spawn watch.watch_by_config(config.watch, mut r_indexer)
		}

		os.signal_opt(.int, fn [mut service, mut rest_server] (signal os.Signal) {
			elegant_exit(mut service, mut rest_server)
		})!
		os.signal_opt(.term, fn [mut service, mut rest_server] (signal os.Signal) {
			elegant_exit(mut service, mut rest_server)
		})!
	}

	threads.wait()
}

fn elegant_exit(mut service core.Service, mut rest_server http.Server) {
	service.close() or {
		panic("Failed to close service")
	}
	rest_server.stop()
	exit(0)
}

fn mapping(mut service core.Service, mut m meta.IndexMapping) ! {
	if service.check_mapping(m)! {
		m.mapping_time = time.now()
		service.save_log(m)
	}
}