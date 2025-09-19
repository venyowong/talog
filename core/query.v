module core

pub struct TagQuery {
pub mut:
	tag Tag
	type int // 0 eq 1 neq
}

pub struct ExpressionQuery {
pub mut:
	left Query
	right Query
	type int // 2 and 3 or
}

type Query = TagQuery | ExpressionQuery

pub fn Query.eq(label string, value string) Query {
	return TagQuery {
		tag: Tag {
			label: label
			value: value
		},
		type: 0
	}
}

pub fn Query.neq(label string, value string) Query {
	return TagQuery {
		tag: Tag {
			label: label
			value: value
		},
		type: 1
	}
}

pub fn (query Query) and_with_tag(tag Tag) Query {
	return query.and(Query {
		tag: tag
		type: 0
	})
}

pub fn (q1 Query) and(q2 Query) Query {
	return ExpressionQuery {
		left: q1
		right: q2
		type: 2
	}
}

pub fn (query Query) is_default() bool {
	match query {
		TagQuery { return query.type == 0 && query.tag.is_default() }
		ExpressionQuery { return query.type == 0 }
	}
}

pub fn (mut query Query) not() Query {
	match mut query {
		TagQuery {
			match mut query.type {
				0 { query.type = 1 }
				1 { query.type = 0 }
				else {}
			}
		}
		ExpressionQuery {
			match mut query.type {
				2 {
					query.type = 3
					query.left.not()
					query.right.not()
				}
				3 {
					query.type = 2
					query.left.not()
					query.right.not()
				}
				else {}
			}
		}
	}
	return query
}

pub fn (query Query) or_with_tag(tag Tag) Query {
	return query.or(Query {
		tag: tag
		type: 0
	})
}

pub fn (q1 Query) or(q2 Query) Query {
	return ExpressionQuery {
		left: q1
		right: q2
		type: 3
	}
}

