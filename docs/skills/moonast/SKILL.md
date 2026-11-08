---
name: moonast
description: "Write a MoonBit code generator for annotations: read the declarations of a file, bind #lib.name(k=v) arguments to typed parameters, and build the generated code from templates. Use for a derive macro, an annotation processor, or any code generated from annotated MoonBit source."
---

# moonast

`moon add moonbitstack/moonast`, then import what the generator uses. A generator
needs three of them: the declarations, the annotations on them, and the code to write.

```text
import {
  "moonbitstack/moonast/attr",
  "moonbitstack/moonast/gen",
  "moonbitstack/moonast/quote",
}
```

## Write a generator

A generator is a type with two methods: the name that goes in the header of every
file it writes, and the code those files hold. `generate` sees every declaration of
every input at once, so one call can answer per declaration or gather them into
one table.

```mbt
struct Getters {}

impl @gen.Generator for Getters with fn name(_) {
  "getters"
}

impl @gen.Generator for Getters with fn generate(_, decls) {
  let out = []
  for decl in decls {
    guard decl is Struct(name~, fields~, attrs~, ..) else { continue }
    guard @attr.find(attrs, "demo.getters") is Some(_) else { continue }
    for field in fields {
      let source =
        #|fn $T::$field(self : $T) -> $Ty {
        #|  self.$field
        #|}
      out.push(
        @quote.items(source)
        .set("T", @quote.ident(name))
        .set("field", @quote.ident(field.name))
        .set("Ty", @quote.ty(field.ty).render())
        .render(),
      )
    }
  }
  @quote.join(out)
}
```

A template is real MoonBit with `$holes`; `render` gives a `Code`, and the printer
lays it out. Do not align the template by hand — the layout is the printer's.

## Read the annotation's arguments

Bind the annotation against a spec, then read the parameters by name. A missing,
unknown, mistyped or repeated argument is refused with the annotation's line and
column instead of producing code.

```mbt
let source =
  #|#demo.getters(skip=token)
  #|pub struct User {
  #|  id : Int
  #|  token : String
  #|}
guard @gen.read("models.mbt", source) is [decl] else { abort("one declaration") }
guard @attr.find(decl.attrs(), "demo.getters") is Some(annotation) else {
  abort("the struct is annotated")
}
let skip = @attr
  .Spec::new("demo.getters")
  .many("skip", Ident)
  .bind(annotation)
  .strs("skip")
assert_eq(skip.join(", "), "token")
```

## Read what a type is

`Decl::shape` is the body of a type: `Empty`, `Tuple`, `Record` or `Cases`. A
variant's payload is the first three, so one `match` covers structs and enums.

```mbt
let source =
  #|pub struct Rgb(Int, Int, Int)
  #|
  #|pub enum Shape {
  #|  Empty
  #|  Circle(Double)
  #|}
let shapes = @gen.read("shapes.mbt", source).map(decl => {
  match decl.shape() {
    Some(Tuple(arity~)) => "\{decl.name()} takes \{arity}"
    Some(Cases(cases~)) => "\{decl.name()} has \{cases.length()} cases"
    _ => "nothing to write"
  }
})
assert_eq(shapes.join("; "), "Rgb takes 3; Shape has 2 cases")
```

## Ship it as a binary

The `main` of a generator binary is one call: `@cli.run(Getters::{ }, @env.args()[1:])`
in an `async fn main`, with `moonbitlang/async` imported. A project that uses it
writes one rule in its `moon.mod` and one line in the `moon.pkg` of the package
whose declarations it reads:

```text
rule(name: "getters", command: "moonx <module>@<version> -C \"$mod_dir\" \"$input\" -o \"$output\"")
dev_build(rule: "getters", input: "models.mbt", output: "getters.g.mbt")
formatter(ignore: [ "getters.g.mbt" ])
```

Add `--check` to the command and the rule only reports a stale output instead of
writing it; line endings are compared after being unified, so a checkout that
turned them into CRLF does not fail.

## Rules that catch people out

- A hole's case is grammar, not style: `$T` where a type or a constructor goes,
  `$name` where a value or a binder goes.
- The annotation grammar has strings, `true`/`false`, names and nested calls. No
  arrays, no numbers; a generic type is written as a string, `response="Array[User]"`,
  and a keyword cannot be a label. A list is a repeated key, `tags="a", tags="b"`,
  or bare arguments, `#demo.derive(A, B)`, which needs `positional=true`.
- An annotation whose payload the parser cannot read has no name, so `find` passes
  over it. Ask `@attr.malformed(attrs, "demo")` first and report what it finds.
- `Decl` keeps a type as the source text that wrote it, which is what a template
  splices. Use `Field::optional` for "is this type `Option`" rather than looking at
  that text: `T?` and `Option[T]` are the same type.
- A generator may only add code. Everything it writes calls interfaces that already
  exist, so a project can use the annotation and the hand-written form side by side.
