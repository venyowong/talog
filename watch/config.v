module watch

import core.structs

pub struct WatchConfig {
pub mut:
	file_name_regex string
	index string
	paths []string
	rule LogRule
	tags []structs.Tag
}