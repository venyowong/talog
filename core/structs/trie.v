module structs

import venyowong.linq
import sync

pub struct Trie {
mut:
	mutex sync.RwMutex = sync.RwMutex{} @[json: '-']
pub mut:
	char string @[json: Char]
	nodes []&Trie @[json: Nodes]
	buckets map[string]Bucket @[json: Buckets]
}

pub fn (mut trie Trie) append(path string, bucket Bucket) {
	trie.mutex.lock()
	defer {trie.mutex.unlock()}

	if path.len == 0 {
		trie.buckets[bucket.key] = bucket
		return
	}

	mut node := trie.get_match_node(path)
	if path.len > 1 {
		node.append(path[1..], bucket)
	} else {
		node.append("", bucket)
	}
}

pub fn (mut trie Trie) get_buckets(path string) []Bucket {
	if path.len == 0 {
		return trie.buckets.values()
	}

	mut node := trie.get_match_node(path)
	if path.len > 1 {
		return node.get_buckets(path[1..])
	} else {
		return node.get_buckets("")
	}
}

pub fn (trie Trie) get_leaves() []string {
	mut leaves := []string{}
	if trie.char.len > 0 && trie.buckets.len > 0 {
		leaves << trie.char
	}
	for node in trie.nodes {
		leaves << linq.map(node.get_leaves(), fn [trie] (l string) string {
			return trie.char + l
		})
	}
	return leaves
}

pub fn (trie Trie) is_default() bool {
	return trie.char.len == 0 && trie.nodes.len == 0 && trie.buckets.len == 0
}

pub fn (mut trie Trie) remove_bucket(path string, key string) {
	if path.len == 0 {
		trie.buckets.delete(key)
		return
	}

	mut node := trie.get_match_node(path)
	if path.len > 1 {
		node.remove_bucket(path[1..], key)
	} else {
		node.remove_bucket("", key)
	}
}

fn (mut trie Trie) get_match_node(path string) &Trie {
	ch := path[0..1]
	return linq.first(trie.nodes, fn [ch] (t Trie) bool {
		return t.char == ch
	}) or { 
		t := Trie{char: ch}
		trie.nodes << &t
		return &t
	}
}