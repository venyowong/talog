module watch

import core.meta

pub struct LogHeader {
pub mut:
	format string
	type string // string/time/number
}

pub struct LogRule {
pub mut:
	log_type meta.LogType
	header_regex string 	// regex of log header, such as:
							// 2025-10-08T01:52:47.025477Z [WARN ] something go wrong, exception: 
							//   error msg
							//   trace
							// you can use `^(?P<time>[^ ]+)` as header_regex
							// you will get `time=2025-10-08T01:52:47.025477Z` and three-line log
	header_condition string // the condition for matched header, such as:
							// [INFO] xxxxxx
							// [2025-10-08T01:52:47.025477Z] xxxxx
							// [WARN] xxxxxx
							// header_regex=^[(?P<level>[^]]+)] and header_condition='level in [INFO,WARN,ERROR]'
							// you will get two logs, first log has two lines
	headers map[string]LogHeader
}