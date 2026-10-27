///|
/// A piece of MoonBit with holes, waiting to be filled and rendered.
///
/// A hole is `$name`; write it in the case the position wants, `$T` where a type
/// or constructor goes and `$name` where a value or a name goes. `$name*` takes a
/// list and expands among statements, array elements or positional arguments.
/// `$$` is a literal dollar sign.
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
}

///|
/// A template of top-level declarations.
pub fn items(source : StringView) -> Template {
  { kind: Items, source: source.to_owned(), ones: Map([]), manys: Map([]), }
}

///|
/// A template of one expression.
pub fn expr(source : StringView) -> Template {
  { kind: Expr, source: source.to_owned(), ones: Map([]), manys: Map([]), }
}

///|
/// A template of one type.
pub fn ty(source : StringView) -> Template {
  { kind: Type, source: source.to_owned(), ones: Map([]), manys: Map([]), }
}

///|
/// Fill `$hole` with `code`.
pub fn Template::set(self : Template, hole : String, code : Code) -> Template {
  let ones = self.ones.copy()
  ones[hole] = code.body
  { ..self, ones, }
}

///|
/// Fill `$hole*` with `codes`, in order.
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
/// is left empty, a fill names no hole, a fill does not fit where it stands, or
/// the template is not MoonBit.
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
  }
  if splicer.misfits.get(0) is Some(first) {
    raise first
  }
  { body, }
}
