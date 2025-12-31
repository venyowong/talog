module structs

fn test_shard() {
	mut s := Shard{}
	s.append_bucket("value1", Bucket {
		file: "file1"
		index: "test"
		key: "key1"
		tags: []Tag{}
	})
	println(s.get_buckets())
}