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

Because my english is poor, I am unable to accurately describe the core principles in English, so I use Chinese to do it.

[Documents](./docs/index.md)