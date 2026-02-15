# Disadvantages of Developing with Vlang

## Obvious Drawbacks

- No dedicated IDE support
- Difficult debugging process

## Unclear Rules for Reference Usage

Vlang automatically applies references in many scenarios. An inspection of the compiled C code reveals that all variables are pointer types. However, in some cases, Vlang will perform value copying--`Closures` being a typical example. You can refer to the `Closures` section in the [official documentation](https://github.com/vlang/v/blob/master/doc/docs.md). To synchronize data modifications between the inside and outside of a closure, you need to pass values by reference explicitly.
For new developers who are just starting with Vlang, it’s common to overlook this detail in the documentation. When they first experiment with `Closures`, they often encounter perplexing issues: changes made to data inside the closure do not reflect outside of it.

In addition, Vlang will automatically convert structs into references in certain contexts. This makes the V code appear to be using structs directly, leading developers to mistakenly assume that structs can be passed around freely. As a result, unexpected situations may arise where variables that are logically the same hold different values. The root cause of this problem is that the underlying code reads from and writes to different references. To resolve such issues, developers need to pay close attention to the details of every parameter passing operation and specify pass-by-reference explicitly whenever possible.