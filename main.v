module main

import cli
import core
import os
import rest
import zmq

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
	data_path := cmd.flags.get_string('data')!
	mut service := core.Service {
		data_path: data_path
	}
	service.setup()!
	defer {service.close() or {
		panic("Failed to close service")
	}}

	host := cmd.flags.get_string("host")!
	mut rest_app := rest.RestApp.new(&service)
	spawn rest_app.run_server(host, cmd.flags.get_int("port")!)

	zmq_port := cmd.flags.get_int("zmq_port")!
	mut zmq_app := zmq.ZmqApp.run(mut service, "tcp://$host:$zmq_port", cmd.flags.get_int("zmq_workers")!)!
	defer {zmq_app.close()}

	os.signal_opt(.int, fn [mut service] (signal os.Signal) {
		service.close() or {
			panic("Failed to close service")
		}
		exit(0)
	})!
	os.signal_opt(.term, fn [mut service] (signal os.Signal) {
		service.close() or {
			panic("Failed to close service")
		}
		exit(0)
	})!
}