module models

pub struct JsonLog[T] {
pub mut:
	json string
	tags []Tag
	value T
}