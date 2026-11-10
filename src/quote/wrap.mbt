///|
/// Expressions and types do not parse on their own, so they are parsed inside a
/// function: an expression as its body, a type as its parameter's.
let wrapper = "moonast__wrap"

///|
/// What a template of match cases is parsed against. Nothing in a rendered code
/// ever names it.
let subject = "moonast__subject"

///|
fn parse(source : String) -> @list.List[@syntax.Impl] raise Refused {
  let (impls, reports) = @parser.parse_string(source)
  if reports.length() > 0 {
    let r = reports[0]
    raise Template(
      msg=r.msg,
      line=r.loc.start.lnum,
      column=r.loc.start.column(),
    )
  }
  impls
}

///|
fn parse_expr(source : String) -> @syntax.Impl raise Refused {
  let impls = parse("fn \{wrapper}() -> Unit {\n" + source + "\n}")
  guard impls is More(impl_, tail=Empty) && impl_ is TopFuncDef(..) else {
    raise Template(msg="expected one expression", line=1, column=1)
  }
  impl_
}

///|
fn parse_type(source : String) -> @syntax.Impl raise Refused {
  let impls = parse("fn \{wrapper}(x : " + source + ") -> Unit {\n  ()\n}")
  guard impls is More(impl_, tail=Empty) && impl_ is TopFuncDef(..) else {
    raise Template(msg="expected one type", line=1, column=1)
  }
  impl_
}

///|
/// Match cases and record fields are parsed the same way, inside the construct
/// that has room for them.
fn parse_cases(source : String) -> @syntax.Impl raise Refused {
  let impls = parse(
    "fn \{wrapper}() -> Unit {\n  match \{subject} {\n" + source + "\n  }\n}",
  )
  guard impls is More(impl_, tail=Empty) &&
    impl_ is TopFuncDef(decl_body=DeclBody(expr=Match(..)), ..) else {
    raise Template(msg="expected match cases", line=1, column=1)
  }
  impl_
}

///|
fn parse_fields(source : String) -> @syntax.Impl raise Refused {
  let impls = parse("fn \{wrapper}() -> Unit {\n  {\n" + source + "\n  }\n}")
  guard impls is More(impl_, tail=Empty) &&
    impl_ is TopFuncDef(decl_body=DeclBody(expr=Record(..)), ..) else {
    raise Template(msg="expected record fields", line=1, column=1)
  }
  impl_
}

///|
/// The cases of a rendered cases template.
fn cases_of(impl_ : @syntax.Impl) -> @list.List[@syntax.Case] {
  guard impl_ is TopFuncDef(decl_body=DeclBody(expr=Match(cases~, ..)), ..) else {
    abort("a cases code is always a wrapped match")
  }
  cases
}

///|
/// The fields of a rendered fields template.
fn fields_of(impl_ : @syntax.Impl) -> @list.List[@syntax.FieldDef] {
  guard impl_ is TopFuncDef(decl_body=DeclBody(expr=Record(fields~, ..)), ..) else {
    abort("a fields code is always a wrapped record")
  }
  fields
}

///|
fn expr_of(impl_ : @syntax.Impl) -> @syntax.Expr {
  guard impl_ is TopFuncDef(decl_body=DeclBody(expr~), ..) else {
    abort("an expression code is always a wrapped function body")
  }
  expr
}

///|
fn type_of(impl_ : @syntax.Impl) -> @syntax.Type {
  guard impl_
    is TopFuncDef(
      fun_decl={ decl_params: Some(More(Positional(ty=Some(t), ..), ..)), .. },
      ..
    ) else {
    abort("a type code is always a wrapped parameter type")
  }
  t
}

///|
/// The printed body of a wrapper function, without the wrapper.
fn unwrap_body(printed : String) -> String {
  let lines = printed.split("\n").map(l => l.to_owned()).to_array()
  let open = lines.search_by(l => l.has_prefix("fn " + wrapper)).unwrap_or(0)
  let mut close = lines.length()
  for i = lines.length() - 1; i > open; i = i - 1 {
    if lines[i] == "}" {
      close = i
      break
    }
  }
  lines[open + 1:close]
  .map(l => if l.has_prefix("  ") { l[2:].to_owned() } else { l })
  .join("\n")
}

///|
/// The printed parameter type of a wrapper function.
fn unwrap_type(printed : String) -> String {
  let start = printed.find("(x : ").unwrap_or(0) + 5
  let end = printed.rev_find(") -> Unit").unwrap_or(printed.length())
  printed[start:end].to_owned()
}
