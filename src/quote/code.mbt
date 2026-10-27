///|
/// A piece of MoonBit: top-level declarations, an expression, a type, a name, or
/// the text of a string literal. Codes come from rendering a template or from the
/// literal constructors here, and fill the holes of other templates.
pub struct Code {
  priv body : Body
}

///|
priv enum Body {
  Items(@list.List[@syntax.Impl])
  Expr(@syntax.Impl)
  Type(@syntax.Impl)
  Name(String)
  Text(String)
}

///|
/// A name: a value, a function, a field, a type or a constructor, optionally
/// qualified as `@pkg.name`. Refused unless it is a well-formed identifier.
pub fn ident(name : StringView) -> Code raise Refused {
  let (pkg, id) = match name.find(".") {
    Some(i) if name.has_prefix("@") => (Some(name[1:i]), name[i + 1:])
    _ => (None, name)
  }
  guard is_identifier(id) &&
    (pkg is None || (pkg is Some(p) && is_identifier(p))) else {
    raise Name(name=name.to_owned())
  }
  { body: Name(name.to_owned()), }
}

///|
/// A string literal holding `text`; quoting and escaping happen when it is printed.
pub fn string(text : StringView) -> Code {
  { body: Text(text.to_owned()), }
}

///|
/// An integer literal.
pub fn int(value : Int32) -> Code {
  { body: Expr(parse_expr(value.to_string())), } catch {
    _ => abort("an integer literal always parses")
  }
}

///|
/// A boolean literal.
pub fn bool(value : Bool) -> Code {
  { body: Expr(parse_expr(if value { "true" } else { "false" })), } catch {
    _ => abort("a boolean literal always parses")
  }
}

///|
/// Several codes of top-level declarations as one, in order.
pub fn join(codes : Array[Code]) -> Code raise Refused {
  let out = []
  for code in codes {
    guard code.body is Items(impls) else { raise Kind(expected="declarations") }
    for item in impls {
      out.push(item)
    }
  }
  { body: Items(@list.List(out)), }
}

///|
/// The official syntax tree behind a code of declarations, for work this package
/// does not cover.
pub fn Code::items(self : Code) -> @list.List[@syntax.Impl]? {
  match self.body {
    Items(impls) => Some(impls)
    _ => None
  }
}

///|
/// Source text through moonbitlang/parser's printer and formatter: the same layout
/// `moon fmt` gives.
pub impl Show for Code with fn output(self, logger) {
  logger.write_string(print(self.body))
}

///|
pub extend Code with Show::{to_string, output}

///|
fn print(body : Body) -> String {
  match body {
    Items(@list.Empty) => ""
    Items(impls) => @fmt.format(@fmt.impls_to_string(impls))
    Expr(w) => unwrap_body(@fmt.impls_to_string(@list.singleton(w)))
    Type(w) => unwrap_type(@fmt.impls_to_string(@list.singleton(w)))
    Name(n) => n
    Text(t) => "\"" + escape(t) + "\""
  }
}

///|
fn is_identifier(s : StringView) -> Bool {
  guard s.length() > 0 else { return false }
  for i, c in s {
    let ok = c is ('a'..<='z' | 'A'..<='Z' | '_') ||
      (i > 0 && c is ('0'..<='9'))
    guard ok else { return false }
  }
  true
}

///|
/// The source form of `text` inside a MoonBit string literal.
fn escape(text : String) -> String {
  let sb = StringBuilder()
  for c in text {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      c if c.to_int() < 0x20 || c.to_int() == 0x7f =>
        sb.write_string("\\u{" + c.to_int().to_string(radix=16) + "}")
      c => sb.write_char(c)
    }
  }
  sb.to_string()
}
