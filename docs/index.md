# Introduction

talog is developed to address the issue where individual developers have limited cloud service resources and cannot deploy heavyweight logging platforms like ELK. Referencing the design philosophy of Loki, talog primarily categorizes logs by tagging them. Logs with the same tags are stored in the same bucket file, and the bucket file name is stored in a trie structure for each tag to enable fast lookup.

### Example

```
log：[2025-11-14 13:16:40.248 +08:00] [INF] Talogger 48590785 init.
tags：
- date: 20251114
- level: INF
```

talog stores the above log in a bucket file with the key `a1de2ce0dee10d7728dfb415ac4c5e38` (essentially appending the log to `a1de2ce0dee10d7728dfb415ac4c5e38.log`).

`a1de2ce0dee10d7728dfb415ac4c5e38 = MD5(date:20251114;level:INF)`

Additionally, talog maintains a separate trie for each tag. This means the corresponding bucket (and thus the relevant logs) can be found using either `date: 20251114` or `level: INF`.

## Tag

When using talog, it is important to carefully design log tags—similar to index mapping in Elasticsearch. The following recommendations apply to tag usage:

- Avoid using too many or too few tags for logs
- The number of enumerations for tag values should be limited

### Avoid Overly Large Bucket Files

If logs have too few tags (e.g., only a `Level` tag with just three enumerations: INF, WRN, ERR), only three bucket files will be created. INFO logs are typically the most numerous, so the corresponding bucket file may grow rapidly to an unmanageable size, leading to degraded query performance.

### Avoid Overly Small Bucket Files

If logs have too many tags, or if tag values are overly granular (with a large or even infinite number of enumerations), numerous bucket files will be created—each potentially storing only a single log entry. This results in a large number of file read operations during queries, impacting performance.

### Recommended Tags

- name: Project name
- level: Log level
- month: YYYYMM
- date: YYYYMMDD

## Core Principles

Talog has three core data structures: index, shard, and bucket.

### Bucket

Talog groups logs with identical tags into the same bucket, where each bucket has a corresponding key and file.

### BucketSet

Talog implements a `BucketSet` structure to store a unique collection of buckets, which is essentially implemented using a map for deduplication.

### Shard

Talog splits data into multiple shards based on different tag dimensions. Each shard stores all tag values and their corresponding bucket collections.
For example, if a log is tagged with `date:20251227;level:INFO;name:TEST_LOG`, Talog stores the log content in the bucket a27f8005db76091215efc91c3ef8fe52.log.

`a27f8005db76091215efc91c3ef8fe52 = MD5("date:20251227;level:INFO;name:TEST_LOG")`

However, three shards will be associated with this bucket:

shard name|tag value|bucket key
---|---|---
date|20251227|a27f8005db76091215efc91c3ef8fe52
level|INFO|a27f8005db76091215efc91c3ef8fe52
name|TEST_LOG|a27f8005db76091215efc91c3ef8fe52

The table above only illustrates the association relationship; the actual storage structure can be referenced in the following code:

```
pub struct Bucket {
pub:
	file string
	index string
	key string
	tags []Tag
}

pub struct BucketSet {
mut:
	buckets []Bucket
	mutex sync.RwMutex @[json: '-']
}

pub struct Shard {
mut:
	m concurrent.AsyncMap[BucketSet]
}
```

### Index

The concept of an index in Talog aligns with Elasticsearch, it stores all buckets used for log storage and maintains a corresponding shard for each tag dimension.

```
pub struct Trie {
pub mut:
	buckets map[string]structs.Bucket
	name string
	shards concurrent.AsyncMap[structs.Shard]
}
```

## api

Before indexing logs, you must first call the `/index/mapping` endpoint to configure index metadata.

### /index/mapping

```
POST http://127.0.0.1:26382/index/mapping
content-type: application/json

{
    "name": "eqp_simulator",
    "log_type": "Raw",
    "log_regex": "\\[(?<date>[^ ]*) (?<time>[^ ]*) \\+08:00\\] \\[(?<level>[^\\]]*)\\] \\[(?<name>[^\\]]*)\\] (?<msg>.*)$",
    "fields": [
        {
            "name": "date",
            "is_tag": true,
            "typ": "String"
        },
        {
          "name": "time",
          "is_tag": false,
          "typ": "String"
        },
        {
            "name": "level",
            "is_tag": true,
            "typ": "String"
        },
        {
            "name": "name",
          "is_tag": true,
          "typ": "String"
        },
        {
            "name": "msg",
          "is_tag": false,
          "typ": "String"
        }
    ],
    "mapping_time": 0
}
```

log_type: Log type (raw for plain text logs, json for structured data)

log_header: Prefix for indexed logs (required if logs contain multiple lines)

log_regex: Regular expression for parsing logs and extracting fields

fields: Parsed log fields (two sources: extracted from logs themselves—either via log_regex for plain text logs or deserialization for JSON data—or log tags). Configuring only tag fields (or no fields at all) does not affect indexing, but talog's built-in admin interface uses these configurations to display fields. For this reason, it is recommended to configure all fields; incomplete configuration may result in some fields not being displayed.

fields.name: field name

fields.is_tag: whether the field is used as an indexing tag

fields.typ: field type — talog supports String and Number

### /index/log

Index a single log entry

```
POST http://127.0.0.1:26382/index/log
content-type: application/json

{
    "name": "eqp_simulator",
    "log_type": "Raw",
    "log": "[2025-09-12 09:24:32.606 +08:00] [INF] [Nucleus] SECS/GEM EAP: --> [0x000007C9] 'S1F14'\n    <L [2] \n        <B [0] >\n        <L [2] \n            <A [6] '8800FC'>\n            <A [5] '1.0.0'>\n        >\n    >\n.\n",
    "tags": [
        {
            "label": "secs",
            "value": "S1F14"
        }
    ],
    "parse_log": true
}
```

tags：Custom tags can be specified additionally when calling this endpoint

### /index/logs

Index multiple log entries. The only difference from indexing a single log is that log is replaced with logs (accepting an array of strings). For multiple logs with identical tags, using this endpoint provides optimal indexing efficiency.

### /index/logs2

Index multiple log entries. The data structure matches `/index`, but the request body accepts an array of objects (each corresponding to a single log entry).

### /index/remove

```
POST http://127.0.0.1:26382/index/remove?name=
```

Physically deletes an entire index (specify the index name via the name query parameter).

### /search/logs

```
http://localhost:26382/search/logs?name=&log_type=raw&query=
```

query：Only supports queries on tag fields. Query syntax follows [fexpr](https://github.com/venyowong/fexpr)
