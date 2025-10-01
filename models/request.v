module models

import core.structs

pub struct IndexLogReq {
pub mut:
	name string
	log_type int
	log string
	tags []structs.Tag
}

