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
  /// The cases of a `match`, kept in the wrapper function they were parsed in.
  /// They have no source form of their own, so printing one takes the wrapper
  /// off again; splicing one hands the cases to a `match` that has a hole where
  /// its case list goes.
  Cases(@syntax.Impl)
  /// The fields of a record, kept the same way. Written `label: value`, the same
  /// text is a labelled argument, so one code fills both places.
  Fields(@syntax.Impl)
}

///|
/// A name: a value, a function, a field, a type or a constructor, optionally
/// qualified as `@pkg.name`. Refused unless it is a well-formed identifier.
///
/// ```mbt check
/// test {
///   inspect(@quote.ident("answer").to_string(), content="answer")
///   inspect(@quote.ident("@web.App").to_string(), content="@web.App")
/// }
/// ```
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
///
/// ```mbt check
/// test {
///   inspect(@quote.string("坐标").to_string(), content="\"坐标\"")
/// }
/// ```
pub fn string(text : StringView) -> Code {
  { body: Text(text.to_owned()), }
}

///|
/// A byte string literal, `b"..."`, holding `text` in UTF-8. Every byte outside
/// printable ASCII is written `\xNN`, so the literal says the same thing in a
/// source file of any encoding; `string` is the text form of the same value.
///
/// ```mbt check
/// test {
///   inspect(@quote.bytes("max-retries").to_string(), content="b\"max-retries\"")
///   inspect(
///     @quote.bytes("坐标").to_string(),
///     content="b\"\\xe5\\x9d\\x90\\xe6\\xa0\\x87\"",
///   )
/// }
/// ```
pub fn bytes(text : StringView) -> Code {
  let out = StringBuilder()
  out.write_string("b\"")
  for byte in @utf8.encode(text.to_owned()) {
    let n = byte.to_int()
    if n == 0x22 || n == 0x5C {
      out.write_char('\\')
      out.write_char(n.unsafe_to_char())
    } else if n >= 0x20 && n <= 0x7E {
      out.write_char(n.unsafe_to_char())
    } else {
      out.write_string("\\x")
      out.write_char(hex_digit(n >> 4))
      out.write_char(hex_digit(n & 0x0F))
    }
  }
  out.write_char('"')
  { body: Expr(parse_expr(out.to_string())), } catch {
    _ => abort("a byte string literal always parses")
  }
}

///|
fn hex_digit(n : Int32) -> Char {
  if n < 10 {
    ('0'.to_int() + n).unsafe_to_char()
  } else {
    ('a'.to_int() + n - 10).unsafe_to_char()
  }
}

///|
/// The bytes of `text` as an array literal of hex, `[0x6e, 0x61]`: one byte each,
/// lowercase, separated by `, `. It is an expression like any array, and a
/// pattern wherever a value of bytes is matched, so a generator that compares a
/// key byte by byte needs neither a string nor an escape. `bytes` writes the same
/// bytes as a `b"..."` literal.
///
/// ```mbt check
/// test {
///   inspect(@quote.byte_array("na").to_string(), content="[0x6e, 0x61]")
///   inspect(
///     @quote.byte_array("坐标").to_string(),
///     content="[0xe5, 0x9d, 0x90, 0xe6, 0xa0, 0x87]",
///   )
/// }
/// ```
pub fn byte_array(text : StringView) -> Code {
  let out = StringBuilder()
  out.write_char('[')
  for i, byte in @utf8.encode(text.to_owned()) {
    if i > 0 {
      out.write_string(", ")
    }
    let n = byte.to_int()
    out.write_string("0x")
    out.write_char(hex_digit(n >> 4))
    out.write_char(hex_digit(n & 0x0F))
  }
  out.write_char(']')
  { body: Expr(parse_expr(out.to_string())), } catch {
    _ => abort("an array literal always parses")
  }
}

///|
/// An integer literal.
///
/// ```mbt check
/// test {
///   inspect(@quote.int(42).to_string(), content="42")
/// }
/// ```
pub fn int(value : Int32) -> Code {
  { body: Expr(parse_expr(value.to_string())), } catch {
    _ => abort("an integer literal always parses")
  }
}

///|
/// A boolean literal.
///
/// ```mbt check
/// test {
///   inspect(@quote.bool(true).to_string(), content="true")
/// }
/// ```
pub fn bool(value : Bool) -> Code {
  { body: Expr(parse_expr(if value { "true" } else { "false" })), } catch {
    _ => abort("a boolean literal always parses")
  }
}

///|
/// Several codes of top-level declarations as one, in order.
///
/// ```mbt check
/// test {
///   let a = @quote.items("fn a() -> Unit { () }").render()
///   let b = @quote.items("fn b() -> Unit { () }").render()
///   inspect(
///     @quote.join([a, b]).to_string(),
///     content="///|\nfn a() -> Unit {\n  ()\n}\n\n///|\nfn b() -> Unit {\n  ()\n}\n",
///   )
/// }
/// ```
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
///
/// ```mbt check
/// test {
///   let code = @quote.items("fn a() -> Unit { () }").render()
///   inspect(code.items() is Some(_), content="true")
/// }
/// ```
pub fn Code::items(self : Code) -> @list.List[@syntax.Impl]? {
  match self.body {
    Items(impls) => Some(impls)
    _ => None
  }
}

///|
/// Source text through the official printer and formatter: the same layout
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
    Items(impls) => print_items(impls)
    Expr(w) => unwrap_body(@fmt.impls_to_string(@list.singleton(w)))
    Type(w) => unwrap_type(@fmt.impls_to_string(@list.singleton(w)))
    Name(n) => n
    Text(t) => "\"" + escape(t) + "\""
    Cases(w) => uncase(unwrap_body(@fmt.impls_to_string(@list.singleton(w))))
    Fields(w) => unfield(unwrap_body(@fmt.impls_to_string(@list.singleton(w))))
  }
}

///|
/// The cases of a printed `match`, one per line, without the `match` that gives
/// them their layout.
fn uncase(text : String) -> String {
  let lines = text.split("\n").map(l => l.to_owned()).to_array()
  guard lines.length() > 2 else { return "" }
  dedent(lines[1:lines.length() - 1])
}

///|
/// The fields of a printed record, without its braces: on one line when the
/// printer kept them there, one per line when it did not.
fn unfield(text : String) -> String {
  if text.has_prefix("{ ") && text.has_suffix(" }") && text.length() > 3 {
    return without_last_comma(text[2:text.length() - 2].to_owned())
  }
  let lines = text.split("\n").map(l => l.to_owned()).to_array()
  guard lines.length() > 2 else { return "" }
  without_last_comma(dedent(lines[1:lines.length() - 1]))
}

///|
/// The printer writes a comma after every field, `{ x: 1, }`; the list a reader
/// gets back reads better without the one at the end.
fn without_last_comma(text : String) -> String {
  if text.has_suffix(",") {
    text[:text.length() - 1].to_owned()
  } else {
    text
  }
}

///|
/// Lines that stood one level inside braces, as they read one level out.
fn dedent(lines : ArrayView[String]) -> String {
  let out = []
  for line in lines {
    out.push(if line.has_prefix("  ") { line[2:].to_owned() } else { line })
  }
  out.join("\n")
}

///|
/// The printer writes a `declare fn` as a `fn` with no body, which does not compile, so those
/// go through one at a time and get the word back.
fn print_items(impls : @list.List[@syntax.Impl]) -> String {
  if !impls.iter().any(declared) {
    return @fmt.format(@fmt.impls_to_string(impls))
  }
  let out = StringBuilder()
  for one in impls {
    let text = @fmt.format(@fmt.impls_to_string(@list.singleton(one)))
    out.write_string(if declared(one) { with_declare(text) } else { text })
  }
  out.to_string()
}

///|
fn declared(one : @syntax.Impl) -> Bool {
  one is TopFuncDef(decl_body=DeclNone, ..)
}

///|
/// `text` with `declare` before the line its function starts on, below any `///` above it.
fn with_declare(text : String) -> String {
  let lines = text.split("\n").map(l => l.to_owned()).to_array()
  for i, line in lines {
    if !line.has_prefix("//") && !line.has_prefix("#") && line != "" {
      lines[i] = "declare " + line
      break
    }
  }
  lines.join("\n")
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
