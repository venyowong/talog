module talog

import core.meta
import watch

pub struct Config {
pub mut:
	mapping []meta.IndexMapping
	watch []watch.WatchConfig
}