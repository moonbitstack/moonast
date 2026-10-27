///|
/// The annotations on the first function in `source`.
fn attrs_of(source : String) -> @list.List[@attribute.Attribute] {
  let (impls, _) = @parser.parse_string(source)
  guard impls is More(TopFuncDef(fun_decl~, ..), ..) else {
    abort("the test source declares a function")
  }
  fun_decl.attrs
}

///|
fn refusal(bind : () -> @attr.Args raise @attr.Refused) -> @attr.Refused? {
  try bind() catch {
    e => Some(e)
  } noraise {
    _ => None
  }
}

///|
let get : @attr.Spec = @attr.Spec::new("app.get")
  .positional("path", Str)
  .optional("summary", Str)
  .optional("deprecated", Bool)
  .optional("style", Ident)
  .optional("response", Type)
  .many("tags", Str)

///|
test "annotations are found by their full name and by their library" {
  let source =
    #|#app.get("/a")
    #|#data.skip
    #|#app.post("/b")
    #|fn f() -> Unit { () }
  let attrs = attrs_of(source)
  assert_eq(attrs.iter().map(@attr.name_of).collect(), [
    Some("app.get"),
    Some("data.skip"),
    Some("app.post"),
  ])
  assert_eq(@attr.find(attrs, "data.skip").map(a => a.raw), Some("#data.skip"))
  assert_eq(@attr.all(attrs, "app.get").length(), 1)
  assert_eq(@attr.under(attrs, "app").map(a => a.raw), [
    "#app.get(\"/a\")", "#app.post(\"/b\")",
  ])
}

///|
test "arguments bind by position, by name and by repetition" {
  let source =
    #|#app.get("/users/{id}", summary="One user", tags="users", tags="admin", deprecated=true, style=plain, response="Array[User]")
    #|fn f() -> Unit { () }
  guard attrs_of(source) is More(attr, ..) else { fail("no annotation") }
  let args = get.bind(attr)
  assert_eq(args.name, "app.get")
  assert_eq(args.str("path"), Some("/users/{id}"))
  assert_eq(args.str("summary"), Some("One user"))
  assert_eq(args.strs("tags"), ["users", "admin"])
  assert_eq(args.bool("deprecated"), Some(true))
  assert_eq(args.str("style"), Some("plain"))
  assert_eq(args.str("response"), Some("Array[User]"))
  assert_eq(args.has("absent"), false)
  let upper = "#app.get(\"/a\", style=Plain)\nfn f() -> Unit { () }"
  guard attrs_of(upper) is More(attr, ..) else { fail("no annotation") }
  assert_eq(get.bind(attr).str("style"), Some("Plain"))
}

///|
test "a required argument left out is refused where the annotation stands" {
  let attrs = attrs_of("\n#app.get(summary=\"x\")\nfn f() -> Unit { () }")
  guard attrs is More(attr, ..) else { fail("no annotation") }
  guard refusal(() => get.bind(attr)) is Some(e) else {
    fail("a missing path binds")
  }
  assert_eq(e.to_string(), "2:1: path is required")
}

///|
test "an unknown, a mistyped or a repeated argument is refused" {
  let cases = [
    ("#app.get(\"/a\", colour=\"red\")", "1:1: there is no colour"),
    ("#app.get(true)", "1:1: path takes a string"),
    (
      "#app.get(\"/a\", summary=\"x\", summary=\"y\")", "1:1: summary is given more than once",
    ),
    (
      "#app.get(\"/a\", response=\"not a type\")", "1:1: response takes a string holding a type",
    ),
    ("#app.get(\"/a\", \"/b\")", "1:1: there is no argument 2"),
  ]
  for case in cases {
    let (source, expected) = case
    let attrs = attrs_of(source + "\nfn f() -> Unit { () }")
    guard attrs is More(attr, ..) else { fail("no annotation") }
    guard refusal(() => get.bind(attr)) is Some(e) else {
      fail("\{source} binds")
    }
    assert_eq(e.to_string(), expected)
  }
}

///|
/// Arrays, numbers, qualified names, and keywords used as labels (`method`,
/// `type`) are outside the annotation grammar of moonbitlang/parser.
test "a payload outside the annotation grammar is refused as malformed" {
  for
    source in [
      "#app.get(tags=[\"a\"])", "#app.get(\"/a\", method=get)", "#app.get(\"/a\", style=@pkg.Plain)",
    ] {
    let attrs = attrs_of(source + "\nfn f() -> Unit { () }")
    guard attrs is More(attr, ..) else { fail("no annotation") }
    guard refusal(() => get.bind(attr)) is Some(Malformed(..)) else {
      fail("\{source} binds")
    }
  }
}
