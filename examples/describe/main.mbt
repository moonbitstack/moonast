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
async fn main {
  @cli.run(Describe::{ }, @env.args()[1:])
}
