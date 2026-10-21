# moonast

Generate MoonBit code from annotated declarations. Built on the official parser, [`moonbitlang/parser`](https://github.com/moonbitlang/parser); moonast does not parse MoonBit itself.

```moonbit
let source =
  #|fn $name() -> $T {
  #|  $value
  #|}
let code = @quote.items(source)
  .set("name", @quote.ident("answer"))
  .set("T", @quote.ident("Int"))
  .set("value", @quote.int(42))
  .render()
println(code) // fn answer() -> Int { 42 }, laid out the way `moon fmt` lays it out
```

## Packages

|  Package  | What it holds |
|:--:|:--|
| `moonast/quote` | Templates: real MoonBit with `$holes`, parsed by moonbitlang/parser, filled by replacing nodes, and printed by its formatter, so quoting, escaping and layout are the official ones |
| `moonast/attr` | Annotations as typed arguments: find `#lib.name(...)` on a declaration and bind its arguments against a spec, with the source position in every refusal |

## Holes

| Hole | Takes | Example |
|:--:|:--|:--|
| `$T` (upper case) | a type or a constructor | `fn f(x : $T)` |
| `$name` (lower case) | a value, an expression, or a name | `self.$name`, `$value + 1` |
| `$name*` | a list, spliced among statements, array elements or positional arguments | `[$items*]` |
| `$name` inside a string literal | a name or a string, as text | `"field $key"` |
| `$$` | a literal `$` | `"$$5"` |

## Annotation arguments

moonbitlang/parser reads strings, `true`/`false`, names and nested calls as annotation arguments. There are no arrays or numbers, a generic or qualified type has to be written as a string, and a keyword (`method`, `type`) cannot be a label. A list is written as a repeated key, `tags="a", tags="b"`, which `Spec::many` accepts.

## Licence

Apache-2.0.
