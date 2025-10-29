module web

import compress.gzip
import os

fn test_gzip() {
	content := "hello world"
	compressed := gzip.compress(content.bytes()) or {panic(err)}
	os.write_bytes("test.gz", compressed) or {panic(err)}
}