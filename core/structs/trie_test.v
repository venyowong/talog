module structs

import json

fn test_trie() {
	mut trie := Trie{}
	trie.append("test", Bucket{
		index: "index"
		key: "key"
		file: "file"
	})
	println(json.encode(trie))
}