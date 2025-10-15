module watch

import core.structs

pub struct WatchConfig {
pub mut:
	dirs []string
	files []string
	index string
	rule LogRule
	tags []structs.Tag
}