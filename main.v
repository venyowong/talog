module main

import cli
import os
import rest
import core

fn main() {
	mut app := cli.Command{
		name:        'v.talog'
		description: 'A local tagging log solution that supports rich communication protocols'
		execute:     run
		flags: [
			cli.Flag {
				flag: cli.FlagType.string
				name: 'data'
				description: 'The path of data, default is ./data/'
				default_value: ['./data/']
			},
			cli.Flag {
				flag: cli.FlagType.int
				abbrev: "p"
				name: 'port'
				description: 'http server port'
				default_value: ['8080']
			},
			cli.Flag {
				flag: cli.FlagType.string
				abbrev: "h"
				name: 'host'
				description: 'http server host'
				default_value: ['localhost']
			}
		]
	}
	app.setup()
	app.parse(os.args)
}

fn run(cmd cli.Command) ! {
	data_path := cmd.flags.get_string('data')!
	mut service := core.Service {
		data_path: data_path
	}
	service.setup()!
	defer {service.close() or {
		panic("Failed to close service")
	}}
	os.signal_opt(.int, fn [mut service] (signal os.Signal) {
		service.close() or {
			panic("Failed to close service")
		}
	})!
	os.signal_opt(.term, fn [mut service] (signal os.Signal) {
		service.close() or {
			panic("Failed to close service")
		}
	})!

	mut rest_app := rest.RestApp.new(&service)
	rest_app.run_server(cmd.flags.get_string("host")!, cmd.flags.get_int("port")!)!
}