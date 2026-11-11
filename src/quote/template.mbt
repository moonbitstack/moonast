///|
/// A piece of MoonBit with holes, waiting to be filled and rendered.
///
/// A hole is `$name`; write it in the case the position wants, `$T` where a type
/// or constructor goes and `$name` where a value or a name goes. `$name*` takes a
/// list and expands among statements, array elements, positional arguments, a
/// match's cases and a record's fields. `$$` is a literal dollar sign.
pub struct Template {
  priv kind : Kind
  priv source : String
  priv ones : Map[String, Body]
  priv manys : Map[String, Array[Body]]
}

///|
priv enum Kind {
  Items
  Expr
  Type
  Cases
  Fields
}

///|
/// A template of top-level declarations.
///
/// ```mbt check
/// test {
///   let code = @quote.items("fn $name() -> $T {\n  $value\n}")
///     .set("name", @quote.ident("answer"))
///     .set("T", @quote.ident("Int"))
///     .set("value", @quote.int(42))
///     .render()
///   inspect(code.to_string(), content="///|\nfn answer() -> Int {\n  42\n}\n")
/// }
/// ```
pub fn items(source : StringView) -> Template {
  { kind: Items, source: source.to_owned(), ones: Map([]), manys: Map([]), }
}

///|
/// A template of one expression.
///
/// ```mbt check
/// test {
///   let code = @quote.expr("$a + $b")
///     .set("a", @quote.int(1))
///     .set("b", @quote.int(2))
///     .render()
///   inspect(code.to_string(), content="1 + 2")
/// }
/// ```
pub fn expr(source : StringView) -> Template {
  { kind: Expr, source: source.to_owned(), ones: Map([]), manys: Map([]), }
}

///|
/// A template of one type.
///
/// ```mbt check
/// test {
///   let code = @quote.ty("Array[$T]").set("T", @quote.ident("User")).render()
///   inspect(code.to_string(), content="Array[User]")
/// }
/// ```
pub fn ty(source : StringView) -> Template {
  { kind: Type, source: source.to_owned(), ones: Map([]), manys: Map([]), }
}

///|
/// A template of match cases, for the hole a `match` has where its case list
/// goes. Each case is `pattern => body`, on its own line, exactly as it is
/// written between the braces of a `match`.
///
/// ```mbt check
/// test {
///   let cases = @quote.cases("$pattern => $value")
///     .set("pattern", @quote.ident("Empty"))
///     .set("value", @quote.int(0))
///     .render()
///   inspect(cases.to_string(), content="Empty => 0")
/// }
/// ```
pub fn cases(source : StringView) -> Template {
  { kind: Cases, source: source.to_owned(), ones: Map([]), manys: Map([]), }
}

///|
/// A template of record fields, for the hole a record has where its field list
/// goes. Each field is `label: value`; the same code fills the arguments of a
/// constructor, where a labelled argument is written the same way.
///
/// ```mbt check
/// test {
///   let fields = @quote.fields("$label: $value")
///     .set("label", @quote.ident("x"))
///     .set("value", @quote.int(1))
///     .render()
///   inspect(fields.to_string(), content="x: 1")
/// }
/// ```
pub fn fields(source : StringView) -> Template {
  { kind: Fields, source: source.to_owned(), ones: Map([]), manys: Map([]), }
}

///|
/// Fill `$hole` with `code`.
///
/// ```mbt check
/// test {
///   let t = @quote.items("fn $name() -> Unit { () }").set(
///     "name",
///     @quote.ident("answer"),
///   )
///   inspect(
///     t.render().to_string(),
///     content="///|\nfn answer() -> Unit {\n  ()\n}\n",
///   )
/// }
/// ```
pub fn Template::set(self : Template, hole : String, code : Code) -> Template {
  let ones = self.ones.copy()
  ones[hole] = code.body
  { ..self, ones, }
}

///|
/// Fill `$hole*` with `codes`, in order.
///
/// ```mbt check
/// test {
///   let code = @quote.expr("[$items*]")
///     .splice("items", [@quote.int(1), @quote.int(2), @quote.int(3)])
///     .render()
///   inspect(code.to_string(), content="[1, 2, 3]")
/// }
/// ```
pub fn Template::splice(
  self : Template,
  hole : String,
  codes : Array[Code],
) -> Template {
  let manys = self.manys.copy()
  manys[hole] = codes.map(c => c.body)
  { ..self, manys, }
}

///|
/// Parse the template with its holes standing as placeholders, put each fill
/// where its placeholder stands, and give back the result. Refused when a hole
/// is left empty, a fill names no hole, a fill does not fit where it stands, the
/// template is not MoonBit, or a hole stands where nothing can be put in its
/// place — the payload of an annotation, a comment — and so would be left in the
/// result as its placeholder.
///
/// ```mbt check
/// test {
///   let text = @quote.items("fn $name() -> Unit { () }").render().to_string() catch {
///       e => e.to_string()
///     }
///   inspect(text, content="hole $name was given nothing")
/// }
/// ```
pub fn Template::render(self : Template) -> Code raise Refused {
  let (text, holes) = scan(self.source)
  let ones = Map([])
  let manys = Map([])
  for hole in holes {
    let at = placeholder(hole)
    if hole.many {
      guard self.manys.get(hole.name) is Some(bodies) else {
        raise Unfilled(hole=hole.name + "*")
      }
      manys[at] = (hole.name, bodies)
    } else {
      guard self.ones.get(hole.name) is Some(body) else {
        raise Unfilled(hole=hole.name)
      }
      ones[at] = (hole.name, body)
    }
  }
  for name, _ in self.ones {
    guard holes.iter().any(h => h.name == name && !h.many) else {
      raise Unused(hole=name)
    }
  }
  for name, _ in self.manys {
    guard holes.iter().any(h => h.name == name && h.many) else {
      raise Unused(hole=name + "*")
    }
  }
  let splicer = { ones, manys, misfits: [], }
  let body : Body = match self.kind {
    Items =>
      Items(parse(text).map(i => @syntax.MapVisitor::visit_Impl(splicer, i)))
    Expr => Expr(@syntax.MapVisitor::visit_Impl(splicer, parse_expr(text)))
    Type => Type(@syntax.MapVisitor::visit_Impl(splicer, parse_type(text)))
    Cases => Cases(@syntax.MapVisitor::visit_Impl(splicer, parse_cases(text)))
    Fields =>
      Fields(@syntax.MapVisitor::visit_Impl(splicer, parse_fields(text)))
  }
  if splicer.misfits.get(0) is Some(first) {
    raise first
  }
  let code : Code = { body, }
  leftover(code, holes)
  code
}

///|
/// Refuse a result that still has a hole in it. Every hole was given something, and
/// every placeholder the fill can stand at was replaced; one that stands in an
/// annotation's payload or in a comment survives, because those are kept as text
/// and no node there can be swapped. Handing the code back would put the
/// placeholder itself in the generated file, where it compiles as an unknown name
/// or, worse, as a name that happens to exist.
fn leftover(code : Code, holes : Array[Hole]) -> Unit raise Refused {
  let text = print(code.body)
  for hole in holes {
    guard text.contains(placeholder(hole)) else { continue }
    raise Leftover(hole=hole.name)
  }
}
