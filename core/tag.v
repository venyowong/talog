module core

pub struct Tag {
pub mut:
	label string @[json: Label]
	value string @[json: Value]
}

pub fn (tag Tag) is_default() bool {
	return tag.label.len == 0
}