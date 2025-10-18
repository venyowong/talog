module talog

import core.meta
import watch

pub struct Config {
pub mut:
	adm_pwd string
	allow_list []string
	jwt_secret string
	mapping []meta.IndexMapping
	server string
	watch []watch.WatchConfig
}