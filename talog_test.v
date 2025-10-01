module talog

// import json
import models
import regex
import x.json2

fn test_talog() {
	l := "[2025-09-12 09:24:32.606 +08:00] [INF] [Nucleus] SECS/GEM EAP: --> [0x000007C9] 'S1F14'    <L [2] \n        <B [0] >\n        <L [2] \n            <A [6] '8800FC'>\n            <A [5] '1.0.0'>\n        >\n    >\n."
	reg := '\\[(?P<time>[^\\]]*)\\] \\[(?P<level>[^\\]]*)\\] \\[(?P<name>[^\\]]*)\\] (?P<msg>.*)$'
	mut re := regex.regex_opt(reg)!
	s, e := re.match_string(l)
	if s < 0 {
		panic("$reg can't match $l")
	}

	mut m := map[string]string{}
	// println(re)
	for name in re.group_map.keys() {
		m[name] = re.get_group_by_name(l, name)
	}
	println(m)
}

fn test_json() {
	j := "{\"name\":\"eqp_simulator\",\"lot_type\":0,\"log\":\"[2025-09-12 09:24:32.606 +08:00] [INF] [Nucleus] SECS/GEM EAP: --> [0x000007C9] 'S1F14'\n    <L [2] \n        <B [0] >\n        <L [2] \n            <A [6] '8800FC'>\n            <A [5] '1.0.0'>\n        >\n    >\n.\n\",\"tags\":[{\"label\":\"SECS\",\"value\":\"S1F14\"}]}"
	println(json2.decode[models.IndexLogReq](j) or {
		panic(err)
	})
}