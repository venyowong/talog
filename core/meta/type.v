module meta

import time
import venyowong.linq

pub struct DynamicValue {
mut:
	tim time.Time
	number f64
	strs []string
	times []time.Time
	nums []f64
pub mut:
	type string
	value string
	is_array bool
}

pub fn DynamicValue.new(type string, value string, is_array bool) !DynamicValue {
	mut result := DynamicValue {
		type: type
		value: value
		is_array: is_array
	}
	if is_array {
		result.strs = result.value.trim_left('[').trim_right(']').split(',')
	}
	if type == "time" {
		if is_array {
			result.times = linq.map(result.strs, fn (s string) time.Time {
				return time.parse(s) or {time.Time{}}
			})
		} else {
			result.tim = time.parse(value)!
		}
	} else if type == "number" {
		if is_array {
			result.nums = linq.map(result.strs, fn (s string) f64 {
				return s.f64()
			})
		} else {
			result.number = result.value.f64()
		}
	}
	return result
}

pub fn (val1 DynamicValue) compare_to(val2 DynamicValue) !int {
	if val1.type != val2.type {
		return error("cannot compare ${val1.type} with ${val2.type}")
	}
	if val1.type == "string" {
		if val1.value == val2.value {
			return 0
		} else if val1.value > val2.value {
			return 1
		} else {
			return -1
		}
	} else if val1.type == "time" {
		if val1.tim == val2.tim {
			return 0
		} else if val1.tim > val2.tim {
			return 1
		} else {
			return -1
		}
	} else if val1.type == "number" {
		if val1.number == val2.number {
			return 0
		} else if val1.number > val2.number {
			return 1
		} else {
			return -1
		}
	} else {
		return error("unsupported value type: $val1.type")
	}
}

pub fn (val1 DynamicValue) like(val2 DynamicValue) !bool {
	if val1.type != "string" || val2.type != "string" {
		return error("like only use in string")
	}

	return val1.value.contains(val2.value)
}

pub fn (val1 DynamicValue) in(val2 DynamicValue) !bool {
	if !val2.is_array {
		return error("val2 must be array")
	}
	if val1.type != val2.type {
		return error("cannot compare ${val1.type} with ${val2.type}")
	}

	if val1.type == "string" {
		return val1.value in val2.strs
	} else if val1.type == "time" {
		return val1.tim in val2.times
	} else if val1.type == "number" {
		return val1.number in val2.nums
	} else {
		return error("unsupported value type: $val1.type")
	}
}