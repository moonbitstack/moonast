///|
/// The refusal messages the guide prints, word for word. A page that quotes a
/// message is a page that breaks when the message changes, so the message is
/// pinned here.
fn guide_args(source : String, spec : @attr.Spec) -> String {
  let (impls, _) = @parser.parse_string(source)
  guard impls is More(TopFuncDef(fun_decl~, ..), ..) else {
    abort("the source declares a function")
  }
  guard fun_decl.attrs.head() is Some(annotation) else {
    abort("the function is annotated")
  }
  try {
    let _ = spec.bind(annotation)
    "bound"
  } catch {
    e => e.to_string()
  }
}

///|
/// The annotation the guide binds four different specs against.
let guide_route : String =
  #|#app.get("/users", summary="List users", tags="users", tags="public")
  #|fn list_users() -> Unit {
  #|  ()
  #|}

///|
test "the four refusals the guide prints" {
  // A spec that never mentions `tags`.
  inspect(
    guide_args(
      guide_route,
      @attr.Spec::new("app.get")
      .positional("path", Str)
      .optional("summary", Str),
    ),
    content="1:1: there is no tags",
  )
  // `path` read as a boolean.
  inspect(
    guide_args(guide_route, @attr.Spec::new("app.get").positional("path", Bool)),
    content="1:1: path takes true or false",
  )
  // `tags` given twice to a spec that allows it once.
  inspect(
    guide_args(
      guide_route,
      @attr.Spec::new("app.get")
      .positional("path", Str)
      .optional("summary", Str)
      .required("tags", Str),
    ),
    content="1:1: tags is given more than once",
  )
  // A required parameter nobody gave.
  inspect(
    guide_args(
      guide_route,
      @attr.Spec::new("app.get")
      .positional("path", Str)
      .optional("summary", Str)
      .many("tags", Str)
      .required("method", Str),
    ),
    content="1:1: method is required",
  )
}

///|
test "a payload outside the grammar has no name, and binding it says what it saw" {
  let source =
    #|#app.get("/users", 1)
    #|fn list_users() -> Unit {
    #|  ()
    #|}
  let (impls, _) = @parser.parse_string(source)
  guard impls is More(TopFuncDef(fun_decl~, ..), ..) else {
    abort("the source declares a function")
  }
  // `find` looks for a name, and this annotation has none.
  inspect(@attr.find(fun_decl.attrs, "app.get") is Some(_), content="false")
  inspect(@attr.under(fun_decl.attrs, "app").length(), content="0")
  // The attribute is still there; binding it refuses with the payload as written.
  guard fun_decl.attrs.head() is Some(annotation) else {
    abort("the annotation is on the declaration")
  }
  let refused = try {
    let _ = @attr.Spec::new("app.get").positional("path", Str).bind(annotation)
    "bound"
  } catch {
    e => e.to_string()
  }
  inspect(
    refused,
    content="1:1: cannot read the arguments of #app.get(\"/users\", 1)",
  )
}

///|
test "the readers the guide tabulates answer in the kind their spec asked for" {
  let source =
    #|#app.get("/users", summary="List users", tags="users", tags="public")
    #|fn list_users() -> Unit {
    #|  ()
    #|}
  let (impls, _) = @parser.parse_string(source)
  guard impls is More(TopFuncDef(fun_decl~, ..), ..) else {
    abort("the source declares a function")
  }
  guard fun_decl.attrs.head() is Some(annotation) else {
    abort("the function is annotated")
  }
  let spec = @attr.Spec::new("app.get")
    .positional("path", Str)
    .optional("summary", Str)
    .many("tags", Str)
  let args = spec.bind(annotation)
  inspect(args.str("path").unwrap_or("/"), content="/users")
  inspect(args.strs("tags").join(", "), content="users, public")
  inspect(args.has("page"), content="false")
  inspect(args.get("tags").length(), content="2")
}

///|
test "a contextual name, a qualified name and a type written as a string" {
  let source =
    #|#app.get("/users", style=plain, response="Array[User]")
    #|fn list_users() -> Unit {
    #|  ()
    #|}
  let (impls, _) = @parser.parse_string(source)
  guard impls is More(TopFuncDef(fun_decl~, ..), ..) else {
    abort("the source declares a function")
  }
  guard fun_decl.attrs.head() is Some(annotation) else {
    abort("the function is annotated")
  }
  let args = @attr.Spec::new("app.get")
    .positional("path", Str)
    .optional("style", Ident)
    .optional("response", Type)
    .bind(annotation)
  inspect(args.str("style").unwrap_or(""), content="plain")
  inspect(args.str("response").unwrap_or(""), content="Array[User]")
}
