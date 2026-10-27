///|
/// The whole surface in one run: read a declaration, bind its annotation, and
/// generate code from both.
fn main {
  tour() catch {
    e => abort("the tour stopped: \{e}")
  }
}

///|
fn tour() -> Unit raise {
  let source =
    #|#app.get("/users", summary="List users", tags="users")
    #|fn list_users() -> Array[String] {
    #|  []
    #|}
  // gen: declarations as plain views.
  guard @gen.read("routes.mbt", source) is [Func(name~, attrs~, ..)] else {
    abort("the tour's source declares one function")
  }
  // attr: the annotation's arguments, typed.
  guard @attr.find(attrs, "app.get") is Some(annotation) else {
    abort("the function is annotated")
  }
  let spec = @attr.Spec::new("app.get")
    .positional("path", Str)
    .optional("summary", Str)
    .many("tags", Str)
  let args = spec.bind(annotation)
  // quote: a template filled with what was read.
  let route =
    #|fn register(app : App) -> Unit {
    #|  app.get($path, $handler)
    #|}
  let code = @quote.items(route)
    .set("path", @quote.string(args.str("path").unwrap_or("/")))
    .set("handler", @quote.ident(name))
    .render()
  println(code)
}
