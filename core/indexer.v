module core

pub struct Indexer {
pub mut:
	index Index
	logs []string
	tags []Tag
}

pub fn (mut indexer Indexer) add_tag(label string, value string) Indexer {
	indexer.tags << Tag { label: label, value: value }
	return indexer
}

pub fn (mut indexer Indexer) add_log(log ...string) Indexer {
	indexer.logs << log
	return indexer
}

pub fn (mut indexer Indexer) save() ! {
	if indexer.logs.len <= 0 {
		panic("There is no logs")
	}
	if indexer.tags.len <= 0 {
		panic("There is no tags")
	}

	indexer.index.push(indexer.tags, ...indexer.logs)!
}