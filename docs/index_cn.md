# 介绍

开发 talog 是为了解决在个人开发者云服务资源有限，无法部署类似 elk 这种重量级的日志平台。talog 参考了 loki 的思路，主要是通过为日志打标签的方式，对日志进行归类，具有相同标签的日志，会被存放到同一个 bucket 文件，然后将 bucket 文件名存放在每个标签的字典树中，以便能够快速查找。

### 示例

```
日志：[2025-11-14 13:16:40.248 +08:00] [INF] Talogger 48590785 init.
标签：
- date: 20251114
- level: INF
```

talog 会将以上日志存放到 key 为 a1de2ce0dee10d7728dfb415ac4c5e38 的 bucket 文件中，其实就是会将日志追加到 a1de2ce0dee10d7728dfb415ac4c5e38.log 文件中

`a1de2ce0dee10d7728dfb415ac4c5e38 = MD5(date:20251114;level:INF)`

并且 talog 会分别对两个标签维护对应的字典树，即通过 `date: 20251114` 或 `level: INF` 均可找到对应 bucket，也就可以找到相应日志了。

## 标签

使用 talog 时需要注意日志标签的建立，类似于 es 的 index mapping，对于标签有以下几点建议：

- 日志不要打上过多或过少标签
- 标签值的枚举数量应该是有限的

### 避免 bucket 文件过大

如果日志的标签过少，例如只有一个 Level，而枚举值只有 INF、WRN、ERR，会导致只有三个 bucket 文件，INFO 日志通常是最多的，因此很有可能对应的 bucket 文件会迅速增长到不适合一次性读取的量级，这样会导致后续查询时性能下降。

### 避免 bucket 文件过小

如果日志的标签过多，或标签值过于细化(即标签值枚举数量较多甚至趋于无限)，会导致产生很多 bucket 文件，而每个 bucket 文件可能只保存了一条记录，如此，后续查询时，会产生大量文件读取操作，影响查询性能。

### 建议标签

- name：项目名称
- level：日志级别
- month：YYYYMM
- date：YYYYMMDD

## 核心原理

talog 有三个核心的数据结构：index、shard、bucket

### bucket

talog 会将具有相同标签的日志放在同一个 bucket 中，每一个 bucket 都有其对应的 key 以及文件

### bucket_set

talog 实现了 BucketSet 结构，用于存储一组 bucket 的不重复集合，但其本质是通过 map 去实现去重的

### shard

talog 根据不同的标签维度，将数据拆分为多个 shard，每个 shard 存储着所有的标签值及其对应的 bucket 集合

例如为日志打上了 `date:20251227;level:INFO;name:TEST_LOG` 标签，talog 会将日志内容存放在 bucket(a27f8005db76091215efc91c3ef8fe52.log) 中

`a27f8005db76091215efc91c3ef8fe52 = MD5("date:20251227;level:INFO;name:TEST_LOG")`

但会有三个 shard 关联到该 bucket

shard 名称|标签值|bucket key
---|---|---
date|20251227|a27f8005db76091215efc91c3ef8fe52
level|INFO|a27f8005db76091215efc91c3ef8fe52
name|TEST_LOG|a27f8005db76091215efc91c3ef8fe52

以上表格只是用于表达其中的关联关系，具体存储结构可参考以下代码：

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

### index

index 的概念与 es 中一致，存储了所有用于存储日志的 bucket，以及为每个标签维度维护了对应的 shard

```
pub struct Trie {
pub mut:
	buckets map[string]structs.Bucket
	name string
	shards concurrent.AsyncMap[structs.Shard]
}
```

## api

在索引日志之前，需要先调用 `/index/mapping` 接口，配置索引元数据

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

log_type：日志类型，raw-普通文本日志 json-结构化数据

log_regex：日志的正则表达式，用于解析日志，从日志中提取字段

fields：日志解析后的字段，有两种来源，一个是从日志本身解析出来的字段，比如普通文本日志通过 log_regex 解析出来，或者 json 数据反序列化而得，另一个是日志标签。只配置标签字段甚至不配置任何字段，都不影响索引，但是 talog 自带的后台页面是根据这边的配置去展示字段的，因此建议配置齐全，如果配置不全，会导致部分字段无法展示

fields.name：字段名

fields.is_tag: 表名字段是否作为标签，用于索引

fields.typ：字段类型，talog 支持 string、number 三种类型

### /index/log

索引单条日志

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

tags：可以在调用此接口时，额外指定自定义标签

### /index/logs

索引多条日志，与索引单条日志的唯一差别在于 log 改为 logs，接收一个字符串数组，当有多条日志，但是标签又是相同的，使用该接口可以获得最佳的索引效率

### /index/logs2

索引多条日志，数据结构与 `/index` 一致，但请求数据接收的是数组

### /index/remove

```
POST http://127.0.0.1:26382/index/remove?name=
```

物理删除整个索引

### /search/logs

```
http://localhost:26382/search/logs?name=&log_type=raw&query=
```

query：只支持对于标签字段的查询，查询语句格式参考 [fexpr](https://github.com/venyowong/fexpr)
