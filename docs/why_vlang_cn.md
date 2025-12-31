# 为什么选择 vlang

## 简洁

1. vlang 中的变量默认是不可空的，如果想要使用可空的变量，需要包装为 `Option`

    ```
    // To create an Option var directly:
    my_optional_int := ?int(none)
    my_optional_string := ?string(none)

    // A version of the function using an option
    fn (r Repo) find_user_by_id2(id int) ?User {
        for user in r.users {
            if user.id == id {
                return user
            }
        }
        return none
    }
    ```

    使用 `or` 对 `Option` 进行拆包并指定默认值

    ```
    fn do_something(s string) ?string {
        if s == 'foo' {
            return 'foo'
        }
        return none
    }

    a := do_something('foo') or { 'default' } // a will be 'foo'
    b := do_something('bar') or { 'default' } // b will be 'default'
	do_something("bar") or {return} // 使用 or 跳出执行
    ```

2. 使用 `!` 传递异常

    ```
    import net.http

    fn f(url string) !string {
        resp := http.get(url)!
        return resp.body
    }
    ```

    http.get 方法会抛出异常，如果在调用处不想处理异常，可使用 `!` 将异常转抛出去

    ```
    import net.http

    fn f(url string) string {
        resp := http.get(url) or {
            // panic(err) 直接中断程序运行，抛出异常信息
            // return err 如果直接返回异常，则方法声明处需要将返回类型改为 !string
            // http.HttpResponse{} 返回默认值
        }
        return resp.body
    }
    ```

    也可使用 `or` 对异常进行处理

3. chan

    通道特性与 go 基本一致，但相较于 java/.net 而言，在线程间的数据交互会更加简单易用

关于 Option 和异常处理，可以翻阅 [官方文档](https://github.com/vlang/v/blob/master/doc/docs.md) `Option/Result types and error handling` 部分

## 高性能

### 编译时反射

java/.net 的反射机制都是基于运行时的，而 vlang 支持编译时反射，可以在编译时将反射代码转换为静态代码，这个机制类似于 rust 的 macro，都是元编程特性

使用 $for 可遍历指定 Struct 的 `.fields`、`.values`、`.attributes`、`.variants`、`.methods`

`.fields` 会返回 `FieldData` 列表，字段如下：

```
// FieldData holds information about a field. Fields reside on structs.
pub struct FieldData {
pub:
	name          string // the name of the field f
	typ           int    // the internal TypeID of the field f,
	unaliased_typ int    // if f's type was an alias of int, this will be TypeID(int)

	attrs  []string // the attributes of the field f
	is_pub bool     // f is in a `pub:` section
	is_mut bool     // f is in a `mut:` section

	is_shared bool // `f shared Abc`
	is_atomic bool // `f atomic int` , TODO
	is_option bool // `f ?string` , TODO

	is_array  bool // `f []string` , TODO
	is_map    bool // `f map[string]int` , TODO
	is_chan   bool // `f chan int` , TODO
	is_enum   bool // `f Enum` where Enum is an enum
	is_struct bool // `f Abc` where Abc is a struct , TODO
	is_alias  bool // `f MyInt` where `type MyInt = int`, TODO

	indirections u8 // 0 for `f int`, 1 for `f &int`, 2 for `f &&int` , TODO
}
```

talog 内部保存 `IndexMapping` 就是利用了编译时反射的特性

```
pub struct IndexMapping {
pub mut:
	name string
	log_type LogType @[tag: "log_type"]
	log_header string // header for log
	log_regex string // regex expression for parsing log
	fields []FieldMapping
	mapping_time time.Time @[tag; index_format: "YYYYMM"]
}

pub fn (mut service Service) save_log[T](value T) {
	mut tags := []structs.Tag{}
	$for field in T.fields {
		tag := get_attribute(field, "tag", field.name)
		if tag != none {
			mut label := tag
			mut value_str := ""
			$if field.typ is time.Time {
				format := get_attribute(field, "index_format", "") or {""}
				if format != "" {
					value_str = value.$(field.name).custom_format(format)
				} else {
					value_str = value.$(field.name).custom_format("YYYY-MM-DD HH:mm:ss")
				}
			} $else {
				value_str = value.$(field.name).str()
			}
			tags << structs.Tag {
				label: label
				value: value_str
			}
		}
	}
	mut index := service.get_or_create_index(T.name)
	index.push(tags, json.encode(value))
}

fn get_attribute(field FieldData, key string, default_value string) ?string {
	attribute := arrays.find_first(field.attrs, fn [key] (a string) bool {
		return a.starts_with(key)
	}) or {
		return none
	}

	strs := attribute.split(":")
	if strs.len > 1 {
		return strs[1].trim_space()
	} else {
		return default_value
	}
}
```

`.values`、`.attributes`、`.variants`、`.methods` 的使用可翻阅 [官方文档](https://github.com/vlang/v/blob/master/doc/docs.md) `Compile time reflection` 部分

### 和 C 一样的性能

vlang 会先将 v 代码编译成人类可读的 C 代码，再使用 c 编译器打包成可执行文件，因此使用 vlang 开发的程序能够获得和 C 程序一样的性能