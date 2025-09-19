module main

import cli
import core
import os

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
	service.setup()
	defer {service.close() or {
		panic("Failed to close service")
	}}

	mut index := service.get_or_create_index("equipment")
	query := core.Query.eq("eqp_name", "Nucleus")
	println(index.search_logs(query, fn (line string, tags []core.Tag) TaggingLog {
		return TaggingLog {
			log: line
			tags: tags
		}
	})!)
}