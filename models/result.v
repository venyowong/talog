module models

pub struct Result {
pub mut:
	code int
	msg string
}

pub struct ResultWithData[T] {
pub mut:
	code int
	msg string
	data T
}

pub fn Result.success(msg string) Result {
	return Result {
		code: 0
		msg: msg
	}
}

pub fn Result.fail(code int, msg string) Result {
	return Result {
		code: code
		msg: msg
	}
}

pub fn Result.success_with[T](data T) ResultWithData[T] {
	return ResultWithData[T] {
		code: 0
		data: data
	}
}