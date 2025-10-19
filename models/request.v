module models

import core.meta
import core.structs

pub struct IndexLogReq {
pub mut:
	name string
	log_type meta.LogType
	log string
	tags []structs.Tag
}

pub struct IndexLogsReq {
pub mut:
	name string
	log_type meta.LogType
	logs []string
	tags []structs.Tag
}