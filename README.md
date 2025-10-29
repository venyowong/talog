# talog
A tiny and simple log solution, talog tag logs to store data in a simple way, so it can be quickly queried

## cli

```
talog> .\talog.exe -help
Usage: v.talog [flags] [commands]

A tiny and simple log solution, talog tag logs to store data in a simple way, so it can be quickly queried

Flags:
  -c  -config         config file, json format
      -data           The path of data, default value is ./data/
  -h  -host           http server host, default value is localhost
  -m  -mode           talog run mode: watch/server/all (required)
  -p  -port           http server port, default value is 26382
      -help           Prints help information.
      -man            Prints the auto-generated manpage.

Commands:
  help                Prints help information.
  man                 Prints the auto-generated manpage.
```

## config

```
{
    "adm_pwd": "123456",
    "allow_list": [
        "192.168.0.0/16",
        "127.0.0.1/32"
    ],
    "jwt_secret": "7aaf118c",
    "mapping": [ // fixed mappings, when talog run as server/all mode, these mappings will be saved
        {
            "name": "eqp_simulator",
            "log_type": "raw", // raw/json
            "log_header": "eqp", // if a log has multi lines, you must set log_header as identification of the start of a new log
            "log_regex": "\\[(?P<time>[^\\]]*)\\] \\[(?P<level>[^\\]]*)\\] \\[(?P<name>[^\\]]*)\\] (?P<msg>.*)$", // talog use log_regex to parse log
            "fields": [
                {
                    "name": "time",
                    "tag_name": "", // if tag_name is empty, talog will not index this field
                    "type": "string", // string/time/number
                    "index_format": "", // if index_format is not empty, talog will use it to format field and generate index value
                    "parse_format": "" // if parse_format is not empty, talog will use it to parse field
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
    ],
    "server": "http://127.0.0.1:26382", // server address is the talog backend host which used to index logs, when you run talog as watch mode
    "watch": [
        {
            "paths": [
                "path/to/log.txt",
                "path/to/dir"
            ], // paths to watch
            "index": "eap",
            "rule": { // log rule
                "log_type": "raw", // raw/json
                "header_regex": "^\\[(?P<time>[^\\]]+)\\]" // regex used to match the starting identifier of a log
            },
            "tags": [ // tags of log
                {
                    "label": "name",
                    "value": "xxx"
                }
            ]
        }
    ]
}
```

## mode

### watch

`-m watch`: run talog to watch files

### server

`-m server`: run talog as backend server, you can index logs/json, and query data by web pages

### all

`-m all`: run talog both watch mode and server mode

## api

[.http](./web/index.http)

## web page

[http://127.0.0.1:26382/index.html](http://127.0.0.1:26382/index.html)