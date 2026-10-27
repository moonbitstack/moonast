///|
/// Replaces placeholders with what their holes were given, at the node where each
/// one stands. A visitor cannot raise, so a fill that does not fit its position is
/// recorded and reported once the walk is over.
priv struct Splicer {
  ones : Map[String, (String, Body)]
  manys : Map[String, (String, Array[Body])]
  misfits : Array[Refused]
}

///|
fn Splicer::misfit(self : Splicer, hole : String, expected : String) -> Unit {
  self.misfits.push(Misfit(hole~, expected~))
}

///|
fn long_ident(name : String) -> @syntax.LongIdent {
  match name.find(".") {
    Some(i) if name.has_prefix("@") =>
      Dot(pkg=name[1:i].to_owned(), id=name[i + 1:].to_owned())
    _ => Ident(name~)
  }
}

///|
/// A list with every list placeholder expanded into the expressions it was given.
fn Splicer::expand(
  self : Splicer,
  exprs : @list.List[@syntax.Expr],
) -> @list.List[@syntax.Expr] {
  let out = []
  for e in exprs {
    match e {
      Ident(id={ name: Ident(name~), .. }, ..) if self.manys.get(name)
        is Some((hole, bodies)) =>
        for body in bodies {
          match body {
            Expr(w) => out.push(expr_of(w))
            Name(n) =>
              out.push(
                @syntax.Expr::Ident(
                  id={ name: long_ident(n), loc: e.loc(), },
                  loc=e.loc(),
                ),
              )
            Text(t) =>
              out.push(@syntax.Expr::Constant(c=String(escape(t)), loc=e.loc()))
            _ => self.misfit(hole, "expressions")
          }
        }
      _ => out.push(e)
    }
  }
  @list.List(out)
}

///|
impl @syntax.MapVisitor for Splicer with fn visit_Expr_Ident(self, id~, loc~) {
  // A list hole that is a block's only statement: the parser gives the block as
  // that one expression, so no sequence is there to expand it into.
  if id.name is Ident(name~) && self.manys.contains(name) {
    let all = self
      .expand(@list.singleton(@syntax.Expr::Ident(id~, loc~)))
      .to_array()
    return match all.pop() {
      None => Unit(loc~, faked=false)
      Some(last) if all.is_empty() => last
      Some(last) => Sequence(exprs=@list.List(all), last_expr=last, loc~)
    }
  }
  if id.name is Ident(name~) && self.ones.get(name) is Some((hole, body)) {
    match body {
      Expr(w) => return expr_of(w)
      Name(n) => return Ident(id={ name: long_ident(n), loc: id.loc, }, loc~)
      Text(t) => return Constant(c=String(escape(t)), loc~)
      _ => self.misfit(hole, "an expression")
    }
  }
  @syntax.MapVisitor::visit_Expr_Ident(@syntax.MapVisitorBase(self), id~, loc~)
}

///|
impl @syntax.MapVisitor for Splicer with fn visit_Expr_Constr(
  self,
  constr~,
  loc~,
) {
  if self.ones.get(constr.name.name) is Some((hole, body)) {
    match body {
      Expr(w) => return expr_of(w)
      Name(n) if !n.has_prefix("@") =>
        return Constr(
          constr={ ..constr, name: { ..constr.name, name: n, }, },
          loc~,
        )
      _ => self.misfit(hole, "a constructor or an expression")
    }
  }
  @syntax.MapVisitor::visit_Expr_Constr(
    @syntax.MapVisitorBase(self),
    constr~,
    loc~,
  )
}

///|
impl @syntax.MapVisitor for Splicer with fn visit_Type_Name(
  self,
  constr_id~,
  tys~,
  loc~,
) {
  if constr_id.id is Ident(name~) && self.ones.get(name) is Some((hole, body)) {
    match body {
      Type(w) => return type_of(w)
      Name(n) => {
        let tys = tys.map(t => @syntax.MapVisitor::visit_Type(self, t))
        return Name(constr_id={ ..constr_id, id: long_ident(n), }, tys~, loc~)
      }
      _ => self.misfit(hole, "a type")
    }
  }
  @syntax.MapVisitor::visit_Type_Name(
    @syntax.MapVisitorBase(self),
    constr_id~,
    tys~,
    loc~,
  )
}

///|
/// A name that is only ever a name: a binder, a label, a field, a qualified path.
fn Splicer::rename(self : Splicer, name : String) -> String? {
  guard self.ones.get(name) is Some((hole, body)) else { return None }
  match body {
    Name(n) if !n.has_prefix("@") => Some(n)
    _ => {
      self.misfit(hole, "a plain name")
      None
    }
  }
}

///|
impl @syntax.MapVisitor for Splicer with fn visit_Binder(self, binder) {
  match self.rename(binder.name) {
    Some(name) => { ..binder, name, }
    None => binder
  }
}

///|
impl @syntax.MapVisitor for Splicer with fn visit_Label(self, label) {
  match self.rename(label.name) {
    Some(name) => { ..label, name, }
    None => label
  }
}

///|
impl @syntax.MapVisitor for Splicer with fn visit_LongIdent_Ident(self, name~) {
  match self.ones.get(name) {
    Some((_, Name(n))) => long_ident(n)
    Some((hole, _)) => {
      self.misfit(hole, "a name")
      Ident(name~)
    }
    None => Ident(name~)
  }
}

///|
/// `@pkg.$name`: the hole is the name inside a package.
impl @syntax.MapVisitor for Splicer with fn visit_LongIdent_Dot(self, pkg~, id~) {
  match self.ones.get(id) {
    Some((_, Name(n))) if !n.has_prefix("@") => Dot(pkg~, id=n)
    Some((hole, _)) => {
      self.misfit(hole, "a plain name after a package")
      Dot(pkg~, id~)
    }
    None => Dot(pkg~, id~)
  }
}

///|
/// A hole inside a string literal is text: a name goes in as written, a string as
/// its escaped content.
impl @syntax.MapVisitor for Splicer with fn visit_Constant(self, c) {
  guard c is String(text) else { return c }
  let mut out = text
  for name, fill in self.ones {
    guard out.contains(name) else { continue }
    let (hole, body) = fill
    match body {
      Name(n) => out = out.replace_all(old=name, new=n)
      Text(t) => out = out.replace_all(old=name, new=escape(t))
      _ => self.misfit(hole, "a name or a string inside a string literal")
    }
  }
  String(out)
}

///|
impl @syntax.MapVisitor for Splicer with fn visit_Expr_Array(
  self,
  exprs~,
  is_iter~,
  loc~,
) {
  @syntax.MapVisitor::visit_Expr_Array(
    @syntax.MapVisitorBase(self),
    exprs=self.expand(exprs),
    is_iter~,
    loc~,
  )
}

///|
impl @syntax.MapVisitor for Splicer with fn visit_Expr_Sequence(
  self,
  exprs~,
  last_expr~,
  loc~,
) {
  let given = exprs.to_array()
  given.push(last_expr)
  let all = self.expand(@list.List(given)).to_array()
  guard all.pop() is Some(last) else { return Unit(loc~, faked=false) }
  let init = @list.List(all)
  @syntax.MapVisitor::visit_Expr_Sequence(
    @syntax.MapVisitorBase(self),
    exprs=init,
    last_expr=last,
    loc~,
  )
}

///|
impl @syntax.MapVisitor for Splicer with fn visit_Expr_Apply(
  self,
  func~,
  args~,
  loc~,
) {
  let out = []
  for arg in args {
    if arg.kind is Positional {
      for e in self.expand(@list.singleton(arg.value)) {
        out.push(@syntax.Argument::{ value: e, kind: Positional, })
      }
    } else {
      out.push(arg)
    }
  }
  @syntax.MapVisitor::visit_Expr_Apply(
    @syntax.MapVisitorBase(self),
    func~,
    args=@list.List(out),
    loc~,
  )
}
