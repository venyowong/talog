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
    "jwt_secret": "7aaf118c"
}
```

## web page

[http://127.0.0.1:26382/index.html](http://127.0.0.1:26382/index.html)

## docs

- 中文版本
  - [index](./docs/index_cn.md)
  - [为什么选择 vlang](./docs/why_vlang_cn.md)
- English Version(Translated by AI from chinese version)
  - [index](./docs/index.md)
  - [Why Choose vlang](./docs/why_vlang.md)

## build from source

1. [install v](https://github.com/vlang/v)
2. install dependencies
    ```
    v install venyowong.concurrent
    v install venyowong.file
    v install venyowong.linq
    ```
    If your network is limited, you can clone [venyowong.concurrent](https://github.com/venyowong/concurrent)、[venyowong.linq](https://github.com/venyowong/linq)、[venyowong.query](https://github.com/venyowong/query) into `~/.vmodules`
3. git clone https://github.com/venyowong/talog
4. change pwd into talog folder `cd talog`
5. build source code `v .`
6. you will get talog/talog.exe(executable program)