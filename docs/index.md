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

### Additional Notes

Although Talog supports three tag value types (string/number/time), all are treated as strings at the underlying level. Therefore, all data can use shards to build indexes.
Talog uses a simple indexing method to achieve fast query performance.

For example:`date: 20251114` is associated with List1 {bucket1, bucket2, bucket3}, `level: INF` is associated with List2 {bucket2, bucket4, bucket5}. This means bucket1, bucket2, and bucket3 contain logs from 2025-11-14, while bucket2, bucket4, and bucket5 contain INFO logs. To query INFO logs from 2025-11-14 using the condition `date == 20251114 && level == INF`, talog first retrieves List1 and List2, then computes their intersection (resulting in bucket2). Thus, bucket2 contains the INFO logs from 2025-11-14.

**A large number of tag enumerations will result in a deep trie structure, increasing index data size and impacting index setup efficiency.**

## Advantages

- Small footprint: Developed in V language, the compiled executable is only 5MB
- Zero runtime dependencies
- Log indexing performance sufficient for small-scale projects

  - /index/logs

    This endpoint accepts multiple logs with identical tags. For example, to store fund NAV data in an index named `fund_nav` using the fund code as a unique tag `fund_code:xxxxxx`, this endpoint can be used to improve indexing efficiency.
    Based on the following test results, indexing a single log takes an average of 0.0134ms (this result is for reference only, as multiple logs trigger only one indexing process when using this endpoint):
    
    ```
    2025-12-27T00:36:26.021000Z [INFO ] index fund_nav logs, total logs: 2319, elapsed: 28
    2025-12-27T00:36:26.480000Z [INFO ] index fund_nav logs, total logs: 3225, elapsed: 55
    2025-12-27T00:36:26.830000Z [INFO ] index fund_nav logs, total logs: 2767, elapsed: 23
    2025-12-27T00:36:27.270000Z [INFO ] index fund_nav logs, total logs: 1768, elapsed: 24
    2025-12-27T00:36:27.603000Z [INFO ] index fund_nav logs, total logs: 3610, elapsed: 47
    2025-12-27T00:36:28.042000Z [INFO ] index fund_nav logs, total logs: 2539, elapsed: 29
    2025-12-27T00:36:28.419000Z [INFO ] index fund_nav logs, total logs: 2763, elapsed: 40
    2025-12-27T00:36:28.712000Z [INFO ] index fund_nav logs, total logs: 1577, elapsed: 30
    ```

  - /index/logs2
  
    This endpoint accepts multiple logs but indexes each one individually. From the following logs, indexing a single log takes an average of 0.06ms:

    ```
    2025-11-26T03:10:31.946000Z [DEBUG] index multi logs, total logs: 10000, elapsed: 1056
    2025-11-26T03:10:33.984000Z [DEBUG] index multi logs, total logs: 10000, elapsed: 333
    2025-11-26T03:10:37.454000Z [DEBUG] index multi logs, total logs: 10000, elapsed: 442
    2025-11-26T03:11:32.538000Z [DEBUG] index multi logs, total logs: 1894, elapsed: 92
    ```
- High log query efficiency
  
  ```
  2025-11-26T03:18:48.954000Z [DEBUG] search eap2 buckets by level == ERR, total buckets: 6, elapsed: 0
  2025-11-26T03:18:49.101000Z [DEBUG] search eap2 logs by level == ERR, total logs: 3067, elapsed: 147
  ```

  The logs above show that talog locates corresponding bucket files extremely quickly (completing in less than 1ms). The remaining time is spent parsing logs. For this reason, it is recommended that each bucket does not store an excessive number of logs to ensure optimal query efficiency.

- Built with Vlang's official web framework (veb) for fast API response times

## api

Before indexing logs, you must first call the `/index/mapping` endpoint to configure index metadata.

### /index/mapping

```
POST http://127.0.0.1:26382/index/mapping
content-type: application/json

{
    "name": "eqp_simulator",
    "log_type": "raw",
    "log_header": "eqp",
    "log_regex": "\\[(?P<time>[^\\.]*)\\.\\d{3} \\+08:00\\] \\[(?P<level>[^\\]]*)\\] \\[(?P<name>[^\\]]*)\\] (?P<msg>.*)$",
    "fields": [
        {
            "name": "time",
            "tag_name": "time",
            "type": "time",
            "index_format": "YYYYMM",
            "parse_format": "YYYY-MM-DD HH:mm:ss"
        },
        {
            "name": "level",
            "tag_name": "level",
            "type": "string"
        },
        {
            "name": "name",
            "tag_name": "name",
            "type": "string"
        },
        {
            "name": "msg",
            "type": "string"
        }
    ]
}
```

log_type: Log type (raw for plain text logs, json for structured data)

log_header: Prefix for indexed logs (required if logs contain multiple lines)

log_regex: Regular expression for parsing logs and extracting fields

fields: Parsed log fields (two sources: extracted from logs themselves—either via log_regex for plain text logs or deserialization for JSON data—or log tags). Configuring only tag fields (or no fields at all) does not affect indexing, but talog's built-in admin interface uses these configurations to display fields. For this reason, it is recommended to configure all fields; incomplete configuration may result in some fields not being displayed.

fields.tag_name：When specified, talog generates corresponding tags based on field values

fields.type：Field type (talog supports string, number, and time)

fields.parse_format：For time fields, talog parses the string using this format (defaults to `YYYY-MM-DD HH:mm:ss` if not configured)

fields.index_format：For time fields with a specified tag_name, this format is used to generate tag values (defaults to `YYYY-MM-DD HH:mm:ss` if not configured)

### /index

Index a single log entry

```
POST http://127.0.0.1:26382/index
content-type: application/json

{
    "name": "eqp_simulator",
    "lot_type": "raw",
    "log": "[2025-09-12 09:24:32.606 +08:00] [INF] [Nucleus] SECS/GEM EAP: --> [0x000007C9] 'S1F14'\n    <L [2] \n        <B [0] >\n        <L [2] \n            <A [6] '8800FC'>\n            <A [5] '1.0.0'>\n        >\n    >\n.\n",
    "tags": [
        {
            "label": "secs",
            "value": "S1F14"
        }
    ]
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

query：Only supports queries on tag fields. The query syntax format is `(key1 > value1 || key2 == 'value2') && key3 != "value3"`，Supported operators include: `>` `>=` `<` `<=` `==` `!=` `||` `&&` `in` `like`
