# Why Choose vlang

## Simplicity

1. Variables in vlang are non-nullable by default. If you need a nullable variable, you must wrap it in an `Option`

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

    Unwrap an `Option` and specify a default value using `or`.

    ```
    fn do_something(s string) ?string {
        if s == 'foo' {
            return 'foo'
        }
        return none
    }

    a := do_something('foo') or { 'default' } // a will be 'foo'
    b := do_something('bar') or { 'default' } // b will be 'default'
    ```

2. Propagate errors using `!`.

    ```
    import net.http

    fn f(url string) !string {
        resp := http.get(url)!
        return resp.body
    }
    ```

    The http.get method may throw an error. If you don't want to handle the error at the call site, use `!` to propagate it upwards.

    ```
    import net.http

    fn f(url string) string {
        resp := http.get(url) or {
            // panic(err) immediately terminates the program and throws the error message
            // return err requires changing the return type to !string in the function declaration
            // http.HttpResponse{} returns the default value
        }
        return resp.body
    }
    ```

    You can also handle errors explicitly with the `or` block.

3. chan

    The channel feature is basically consistent with Go. Compared to Java/.NET, data interaction between threads is much simpler and easier to use.

For more details on Option and error handling, refer to the `Option/Result types and error handling` section in the [official documentation](https://github.com/vlang/v/blob/master/doc/docs.md).

## High Performance

### Compile-Time Reflection

Reflection mechanisms in Java/.NET are all runtime-based, while vlang supports compile-time reflection, which converts reflection code into static code during compilation. This mechanism is similar to Rust macros, both belonging to metaprogramming features.

Use `$for` to iterate over the `.fields`、`.values`、`.attributes`、`.variants`、`.methods` of a specified struct.

`.fields` returns a list of `FieldData` structs with the following fields:

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

The internal storage of `IndexMapping` in talog leverages the power of compile-time reflection.

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

For usage examples of `.values`、`.attributes`、`.variants`、`.methods` , refer to the `Compile time reflection` section in the [official documentation](https://github.com/vlang/v/blob/master/doc/docs.md).

### Performance Comparable to C

vlang first compiles V code into human-readable C code, then uses a C compiler to package it into an executable file. Therefore, programs developed with vlang can achieve performance on par with C programs.