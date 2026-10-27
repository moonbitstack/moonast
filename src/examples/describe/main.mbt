///|
struct Describe {}

///|
impl @gen.Generator for Describe with fn name(_) {
  "describe"
}

///|
impl @gen.Generator for Describe with fn generate(_, decls) {
  let out = []
  for decl in decls {
    guard decl is Struct(name~, fields~, attrs~, ..) &&
      @attr.find(attrs, "demo.describe") is Some(_) else {
      continue
    }
    let text = name + "(" + fields.map(f => f.name).join(", ") + ")"
    let source =
      #|fn $T::describe(self : $T) -> String {
      #|  ignore(self)
      #|  $text
      #|}
    out.push(
      @quote.items(source)
      .set("T", @quote.ident(name))
      .set("text", @quote.string(text))
      .render(),
    )
  }
  @quote.join(out)
}

///|
/// With no arguments it reads the bundled declarations, so the example runs as is.
async fn main {
  let args = @env.args()[1:]
  let args = if args.is_empty() {
    ["src/examples/describe/models.txt", "-o", "_build/describe.g.mbt"][:]
  } else {
    args
  }
  @cli.run(Describe::{ }, args)
}
