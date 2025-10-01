module structs

import x.json2

pub struct LogModel {
pub mut:
	log string
	tags []Tag
	data json2.Any
}