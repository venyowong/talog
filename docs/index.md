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

```
pub struct Trie {
pub mut:
	char string
	nodes []&Trie
	buckets map[string]Bucket
}
```

talog 最核心的数据结构为 Trie，该结构为普通的字典树，虽然 talog 支持的标签值有 string/number/time 三种类型，但是底层均是作为字符串，所以所有的数据都可以使用字典树去构建索引。每一个节点都会维护当前标签值所对应的 bucket 列表。

例如：`date: 20251114` 关联了 `List1 {bucket1, bucket2, bucket3}`，`level: INF` 关联了 `List2 {bucket2, bucket4, bucket5}`，即 bucket1、bucket2、bucket3 是 2025-11-14 的日志，而 bucket2、bucket4、bucket5 为 INFO 日志。当想要查询 2025-11-14 的 INFO 日志时，可使用 `date == 20251114 && level == INF`, talog 会先查询到 List1、List2，然后将二者取交集，得到 bucket2，因此可知，bucket2 中存储的是 2025-11-14 的 INFO 日志。

talog 使用了简单的索引方式，因此才能得到较快的查询性能，但这也带来了日志标签的局限性。

**如果标签枚举值数量较多，就会导致字典树层数较深，从而导致索引数据增大，影响索引 setup 效率**

## 优势

- 体积小，使用 vlang 语言开发，编译出来的可执行文件只有 4M
- 不依赖任何运行环境
- 日志索引性能能够满足小型项目需求

  - /index/logs2
  
    该接口接收多条日志，但是会对每一条日志单独索引，因此测试的是索引一条日志所需要的平均时长，从以下日志可计算出，平均索引一条日志需要 0.06ms

    ```
    2025-11-26T03:10:31.946000Z [DEBUG] index multi logs, total logs: 10000, elapsed: 1056
    2025-11-26T03:10:33.984000Z [DEBUG] index multi logs, total logs: 10000, elapsed: 333
    2025-11-26T03:10:37.454000Z [DEBUG] index multi logs, total logs: 10000, elapsed: 442
    2025-11-26T03:11:32.538000Z [DEBUG] index multi logs, total logs: 1894, elapsed: 92
    ```
- 日志查询效率高
  
  ```
  2025-11-26T03:18:48.954000Z [DEBUG] search eap2 buckets by level == ERR, total buckets: 6, elapsed: 0
  2025-11-26T03:18:49.101000Z [DEBUG] search eap2 logs by level == ERR, total logs: 3067, elapsed: 147
  ```

  通过以上日志可看出，talog 查找对应的 bucket 文件是非常快的，不到 1ms 就完成了，剩下的时间都用在解析日志上了，因此建议一个 bucket 不要存储太多日志，这样才能够保证查询的效率

- 使用 vlang 官方 web 框架 veb 开发 api，响应速度快

## api

在索引日志之前，需要先调用 `/index/mapping` 接口，配置索引元数据

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

log_type：日志类型，raw-普通文本日志 json-结构化数据

log_header：索引后的日志前缀，当一条日志有多行时，需要配置该字段

log_regex：日志的正则表达式，用于解析日志，从日志中提取字段

fields：日志解析后的字段，有两种来源，一个是从日志本身解析出来的字段，比如普通文本日志通过 log_regex 解析出来，或者 json 数据反序列化而得，另一个是日志标签。只配置标签字段甚至不配置任何字段，都不影响索引，但是 talog 自带的后台页面是根据这边的配置去展示字段的，因此建议配置齐全，如果配置不全，会导致部分字段无法展示

fields.tag_name：指定了 tag_name，talog 会根据字段值生成对应的标签

fields.type：字段类型，talog 支持 string、number、time 三种类型

fields.parse_format：如果是 time 字段，talog 会使用 parse_format 去解析字符串，如果未配置则默认会使用 `YYYY-MM-DD HH:mm:ss` 格式进行解析

fields.index_format：如果是 time 字段，并且指定了 tag_name，则会使用 index_format 去生成标签值，如果未配置默认会使用 `YYYY-MM-DD HH:mm:ss` 格式

### /index

索引单条日志

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

query：只支持对于标签字段的查询，查询语句格式为 `(key1 > value1 || key2 == 'value2') && key3 != "value3"`，运算符支持 `>` `>=` `<` `<=` `==` `!=` `||` `&&` `in` `like`
