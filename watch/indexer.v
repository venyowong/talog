module watch

import core
import core.meta
import core.structs
import json
import models
import net.http

pub interface Indexer {
mut:
	index_log(log_type meta.LogType, name string, tags []structs.Tag, l string) !bool
}

pub struct InnerIndexer {
pub mut:
	service core.Service
}

pub fn (mut indexer InnerIndexer) index_log(log_type meta.LogType, name string, tags []structs.Tag, l string) !bool {
	return indexer.service.index_log(log_type, name, tags, true, l)!
}

pub struct HttpIndexer {
pub:
	host string
}

pub fn (mut indexer HttpIndexer) index_log(log_type meta.LogType, name string, tags []structs.Tag, l string) !bool {
	res := http.post("${indexer.host}/index", json.encode(models.IndexLogReq {
		name: name
		log_type: log_type
		log: l
		tags: tags
	}))!
	if res.status() != .ok {
		return error("failed to post ${indexer.host}/index, status: ${res.status()}")
	}
	result := json.decode(models.Result, res.body)!
	if result.code != 0 {
		return error(result.msg)
	}

	return true
}