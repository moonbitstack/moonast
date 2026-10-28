///|
/// A generator that takes arguments: `#demo.getters` on a struct gives every
/// field a getter, and `skip=` names the fields that get none.
struct Getters {}

///|
impl @gen.Generator for Getters with fn name(_) {
  "getters"
}

///|
impl @gen.Generator for Getters with fn generate(_, decls) {
  let out = []
  for decl in decls {
    guard decl is Struct(name~, fields~, attrs~, ..) else { continue }
    guard @attr.find(attrs, "demo.getters") is Some(annotation) else {
      continue
    }
    let skip = @attr.Spec::new("demo.getters")
      .many("skip", Ident)
      .bind(annotation)
      .strs("skip")
    for field in fields {
      guard !skip.contains(field.name) else { continue }
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

///|
/// With no arguments it reads the bundled declarations, so the example runs as is.
async fn main {
  let args = @env.args()[1:]
  let args = if args.is_empty() {
    ["src/examples/getters/models.txt", "-o", "_build/getters.g.mbt"][:]
  } else {
    args
  }
  @cli.run(Getters::{ }, args)
}
