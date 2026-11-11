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
/// Numbers, and keywords used as labels (`method`, `type`), are outside the
/// annotation grammar of moonbitlang/parser.
test "a payload outside the annotation grammar is refused as malformed" {
  for source in ["#app.get(page=1)", "#app.get(\"/a\", method=get)"] {
    let attrs = attrs_of(source + "\nfn f() -> Unit { () }")
    guard attrs is More(attr, ..) else { fail("no annotation") }
    guard refusal(() => get.bind(attr)) is Some(Malformed(..)) else {
      fail("\{source} binds")
    }
  }
}

///|
test "an annotation that does not parse is found by its prefix, and no other" {
  let source = "#app.get(type=\"x\")\n#other.thing(type=\"y\")\n#app.post(\"/a\")\nfn f() -> Unit {}"
  let impls = @parser.parse_string(source).0
  guard impls is @list.More(impl_, tail=@list.Empty) else {
    fail("one declaration")
  }
  guard impl_ is @syntax.TopFuncDef(fun_decl={ attrs, .. }, ..) else {
    fail("a function")
  }
  let broken = @attr.malformed(attrs, "app")
  assert_eq(broken.length(), 1)
  assert_true(broken[0].raw.has_prefix("#app.get"))
  assert_eq(@attr.under(attrs, "app").length(), 1)
  assert_eq(@attr.malformed(attrs, "missing").length(), 0)
}

///|
test "a positional parameter marked optional can be left out, and a required one cannot" {
  let attrs = (source : String) => {
    let impls = @parser.parse_string(source + "\nfn f() -> Unit {}").0
    guard impls
      is @list.More(
        @syntax.TopFuncDef(fun_decl={ attrs, .. }, ..),
        tail=@list.Empty
      ) else {
      abort("one function")
    }
    attrs
  }
  let spec = @attr.Spec::new("orm.table").positional("name", Str, optional=true)
  guard @attr.find(attrs("#orm.table"), "orm.table") is Some(bare) else {
    fail("annotated")
  }
  assert_eq(spec.bind(bare).str("name"), None)
  guard @attr.find(attrs("#orm.table(\"heroes\")"), "orm.table") is Some(given) else {
    fail("annotated")
  }
  assert_eq(spec.bind(given).str("name"), Some("heroes"))
  let strict = @attr.Spec::new("orm.table").positional("name", Str)
  let missing = try {
    ignore(strict.bind(bare))
    false
  } catch {
    Missing(key="name", ..) => true
    _ => false
  }
  assert_true(missing)
}

///|
test "a name after a qualifier is a path, and a bare name reads the same" {
  let source = "#demo.bind(contract=registry.create)\nfn f() -> Unit { () }"
  let (impls, _) = @parser.parse_string(source)
  guard impls is @list.More(impl_, tail=@list.Empty) else {
    fail("one declaration")
  }
  guard impl_ is TopFuncDef(fun_decl~, ..) else { fail("a function") }
  guard @attr.find(fun_decl.attrs, "demo.bind") is Some(annotation) else {
    fail("annotated")
  }
  let spec = @attr.Spec::new("demo.bind").required("contract", Path)
  assert_eq(spec.bind(annotation).str("contract"), Some("registry.create"))
  let bare = @attr.Spec::new("demo.bind").required("contract", Ident)
  let refused = try {
    ignore(bare.bind(annotation))
    false
  } catch {
    Mistyped(key="contract", ..) => true
    _ => false
  }
  assert_true(refused)
}

///|
test "a list of positional arguments is one parameter taken many times" {
  let source = "#demo.derive(Serialize, Deserialize)\nstruct P {\n  x : Int\n}"
  let (impls, _) = @parser.parse_string(source)
  guard impls is @list.More(impl_, tail=@list.Empty) else {
    fail("one declaration")
  }
  guard impl_ is TopTypeDef(decl) else { fail("a type") }
  guard @attr.find(decl.attrs, "demo.derive") is Some(annotation) else {
    fail("annotated")
  }
  let spec = @attr.Spec::new("demo.derive").many(
    "trait",
    Ident,
    positional=true,
  )
  assert_eq(spec.bind(annotation).strs("trait"), ["Serialize", "Deserialize"])
  let one = @attr.Spec::new("demo.derive").positional(
    "trait",
    Ident,
    optional=true,
  )
  let refused = try {
    ignore(one.bind(annotation))
    false
  } catch {
    Unknown(key="argument 2", ..) => true
    _ => false
  }
  assert_true(refused)
}

///|
test "a repeating positional comes after the ones that take one value each" {
  let source = "#demo.route(GET, \"users\", \"admin\")\nfn f() -> Unit { () }"
  let (impls, _) = @parser.parse_string(source)
  guard impls is @list.More(impl_, tail=@list.Empty) else {
    fail("one declaration")
  }
  guard impl_ is TopFuncDef(fun_decl~, ..) else { fail("a function") }
  guard @attr.find(fun_decl.attrs, "demo.route") is Some(annotation) else {
    fail("annotated")
  }
  let spec = @attr.Spec::new("demo.route")
    .positional("method", Ident)
    .many("tag", Str, positional=true)
  let args = spec.bind(annotation)
  assert_eq(args.str("method"), Some("GET"))
  assert_eq(args.strs("tag"), ["users", "admin"])
}

///|
test "a refusal names the file when the caller says which file it read" {
  let attrs = attrs_of("\n#app.get(summary=\"x\")\nfn f() -> Unit { () }")
  guard attrs is More(attr, ..) else { fail("no annotation") }
  guard refusal(() => get.bind(attr, file="models.mbt")) is Some(e) else {
    fail("a missing path binds")
  }
  assert_eq(e.to_string(), "models.mbt:2:1: path is required")
  guard e is Missing(file="models.mbt", ..) else {
    fail("the file is on the refusal")
  }
}

///|
test "the file an annotation was bound from is on its arguments" {
  let attrs = attrs_of("#app.get(\"/a\")\nfn f() -> Unit { () }")
  guard attrs is More(attr, ..) else { fail("no annotation") }
  assert_eq(get.bind(attr, file="routes.mbt").file, "routes.mbt")
  assert_eq(get.bind(attr).file, "")
}

///|
test "every problem is reported when the caller asks for all of them" {
  let source =
    #|#app.get(path=true, style=plain, page="1", page="2", extra="y")
    #|fn f() -> Unit { () }
  guard attrs_of(source) is More(attr, ..) else { fail("no annotation") }
  let spec = @attr.Spec::new("app.get")
    .positional("path", Str)
    .optional("style", Bool)
    .optional("page", Str)
  guard refusal(() => spec.bind(attr, all=true)) is Some(e) else {
    fail("four problems bind")
  }
  guard e is Several(errors~) else { fail("the refusal carries every problem") }
  assert_eq(errors.length(), 4)
  assert_eq(
    e.to_string(),
    "1:1: path takes a string\n1:1: style takes true or false\n1:1: page is given more than once\n1:1: there is no extra",
  )
}

///|
test "the first problem is the one raised by default" {
  let source = "#app.get(path=true, extra=\"y\")\nfn f() -> Unit { () }"
  guard attrs_of(source) is More(attr, ..) else { fail("no annotation") }
  let spec = @attr.Spec::new("app.get").positional("path", Str)
  guard refusal(() => spec.bind(attr)) is Some(e) else {
    fail("a mistyped path binds")
  }
  guard e is Mistyped(key="path", ..) else {
    fail("the first problem is the one raised")
  }
  assert_eq(e.to_string(), "1:1: path takes a string")
}

///|
test "an argument given but not read is not reported missing as well" {
  let source = "#app.get(path=true)\nfn f() -> Unit { () }"
  guard attrs_of(source) is More(attr, ..) else { fail("no annotation") }
  let spec = @attr.Spec::new("app.get").positional("path", Str)
  guard refusal(() => spec.bind(attr, all=true)) is Some(e) else {
    fail("a boolean path binds")
  }
  guard e is Several(errors~) else { fail("the refusal carries every problem") }
  assert_eq(errors.length(), 1)
  assert_eq(e.to_string(), "1:1: path takes a string")
}

///|
test "all and the file are given together" {
  let source = "#app.get(1)\nfn f() -> Unit { () }"
  guard attrs_of(source) is More(attr, ..) else { fail("no annotation") }
  let spec = @attr.Spec::new("app.get").positional("path", Str)
  guard refusal(() => spec.bind(attr, file="models.mbt", all=true)) is Some(e) else {
    fail("a malformed payload binds")
  }
  assert_eq(
    e.to_string(),
    "models.mbt:1:1: cannot read the arguments of #app.get(1)",
  )
}

///|
test "an array is the list a repeated key writes, written once" {
  let source =
    #|#app.get("/a", tags=["a", "b"], summary="one")
    #|fn f() -> Unit { () }
  guard attrs_of(source) is More(attr, ..) else { fail("no annotation") }
  let args = get.bind(attr)
  assert_eq(args.str("path"), Some("/a"))
  assert_eq(args.strs("tags"), ["a", "b"])
  assert_eq(args.str("summary"), Some("one"))
}

///|
test "an array of two where one value goes is a repetition" {
  let source = "#app.get(\"/a\", summary=[\"x\", \"y\"])\nfn f() -> Unit { () }"
  guard attrs_of(source) is More(attr, ..) else { fail("no annotation") }
  guard refusal(() => get.bind(attr)) is Some(Repeated(key="summary", ..)) else {
    fail("two summaries bind")
  }
}

///|
test "the elements of an array are read in the kind its parameter takes" {
  let source = "#demo.bind(contract=[registry.create, other.make])\nfn f() -> Unit { () }"
  guard attrs_of(source) is More(attr, ..) else { fail("no annotation") }
  let spec = @attr.Spec::new("demo.bind").many("contract", Path)
  assert_eq(spec.bind(attr).strs("contract"), ["registry.create", "other.make"])
  let wrong = @attr.Spec::new("demo.bind").many("contract", Bool)
  guard refusal(() => wrong.bind(attr)) is Some(Mistyped(key="contract", ..)) else {
    fail("a name binds as a boolean")
  }
}

///|
test "a qualified payload reads as its qualifier and name" {
  let source = "#demo.bind(contract=@pkg.create)\nfn f() -> Unit { () }"
  guard attrs_of(source) is More(attr, ..) else { fail("no annotation") }
  let spec = @attr.Spec::new("demo.bind").required("contract", Path)
  assert_eq(spec.bind(attr).str("contract"), Some("pkg.create"))
}
