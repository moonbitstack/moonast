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
| `moonast/gen` | Declarations read into plain views (`Struct`, `Enum`, `Func`, with types as written), the `Generator` trait, and `render`, which gives the file a generator writes |
| `moonast/cli` | `run`, the whole `main` of a generator binary: `[-C <dir>] <inputs...> -o <output> [--check]`; native and wasm |

`quote`, `attr` and `gen` build for every target; `cli` touches files and builds for native and wasm, which is what `moonx` runs. `moon run examples/tour` shows the first three together, and `examples/describe` is a complete generator.

## Holes

| Hole | Takes | Example |
|:--:|:--|:--|
| `$T` (upper case) | a type or a constructor | `fn f(x : $T)` |
| `$name` (lower case) | a value, an expression, or a name | `self.$name`, `$value + 1` |
| `@pkg.$name` | a name inside a package | `app : @web.$T` |
| `$name*` | a list, spliced among statements, array elements or positional arguments | `[$items*]` |
| `$name` inside a string literal | a name or a string, as text | `"field $key"` |
| `$$` | a literal `$` | `"$$5"` |

## Annotation arguments

moonbitlang/parser reads strings, `true`/`false`, names and nested calls as annotation arguments. There are no arrays or numbers, a generic or qualified type has to be written as a string, and a keyword (`method`, `type`) cannot be a label. A list is written as a repeated key, `tags="a", tags="b"`, which `Spec::many` accepts.

## Writing a generator

A generator implements `Generator`: given every declaration of its inputs, the code to write. Its `main` is one line:

```moonbit
async fn main {
  @cli.run(Describe::{}, @env.args()[1:])
}
```

Publish it as a module whose root package is that executable, and its users wire it into their build. In `moon.mod`:

```
rule(name: "describe", command: "moonx <module>@<version> -C \"$mod_dir\" \"$input\" -o \"$output\"")
```

and in the `moon.pkg` of the package whose declarations it reads:

```
dev_build(rule: "describe", input: "models.mbt", output: "describe.g.mbt")
formatter(ignore: [ "describe.g.mbt" ])
```

`moon check`, `moon build` and `moon run` then regenerate the file whenever `models.mbt` changes. `-C` makes the paths moon passes relative to the module directory, which matters because the rule does not run there. A project that prefers to commit generated files runs the generator with `--check` in CI, which fails when the output is stale.

## Licence

Apache-2.0.
