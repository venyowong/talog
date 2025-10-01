module structs

pub struct Tag {
pub mut:
	label string
	value string
}

pub fn (tag Tag) is_default() bool {
	return tag.label.len == 0
}