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
/// The same for the arguments of a call: a field code fills the place where a
/// labelled argument goes, since `label: value` and `label=value` are one field
/// written for two positions.
fn Splicer::expand_arguments(
  self : Splicer,
  args : @list.List[@syntax.Argument],
) -> @list.List[@syntax.Argument] {
  let out = []
  for arg in args {
    let fill = match (arg.kind, arg.value) {
      (Positional, Ident(id={ name: Ident(name~), .. }, ..)) =>
        self.manys.get(name)
      _ => None
    }
    match fill {
      None => out.push(arg)
      Some((hole, bodies)) =>
        for body in bodies {
          match body {
            Expr(w) => out.push({ value: expr_of(w), kind: Positional, })
            Name(n) =>
              out.push({
                value: @syntax.Expr::Ident(
                  id={ name: long_ident(n), loc: arg.value.loc(), },
                  loc=arg.value.loc(),
                ),
                kind: Positional,
              })
            Text(t) =>
              out.push({
                value: Constant(c=String(escape(t)), loc=arg.value.loc()),
                kind: Positional,
              })
            Fields(w) =>
              for field in fields_of(w) {
                out.push({ value: field.expr, kind: Labelled(field.label), })
              }
            _ => self.misfit(hole, "expressions or record fields")
          }
        }
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
    return chain(all[:], Unit(loc~, faked=false))
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
/// A hole where a constructor stands, in an expression or in a pattern: the name
/// of the constructor the fill gives. A constructor is written upper case, and so
/// is the hole, which is what lets a pattern with arguments take one.
impl @syntax.MapVisitor for Splicer with fn visit_Constructor(self, constr) {
  match self.ones.get(constr.name.name) {
    Some((_, Name(n))) if !n.has_prefix("@") =>
      { ..constr, name: { ..constr.name, name: n, }, }
    Some((hole, _)) => {
      self.misfit(hole, "a constructor name")
      constr
    }
    None =>
      @syntax.MapVisitor::visit_Constructor(
        @syntax.MapVisitorBase(self),
        constr,
      )
  }
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
/// A fill for a pattern hole that is an array of literals, `[0x6e, 0x61]`: the
/// array literal an expression position takes is the array pattern a pattern
/// position takes, element for element. A byte array is how a key is matched
/// without a string, and it is the only array a pattern hole takes; a pattern
/// with a binder or a spread in it is not a constant, so it is not this.
fn constant_array(expr : @syntax.Expr) -> @syntax.Pattern? {
  guard expr is Array(exprs~, is_iter=false, ..) else { return None }
  let pats = []
  for one in exprs {
    guard one is Constant(c~, ..) else { return None }
    pats.push(@syntax.ArrayPattern::Pattern(Constant(c~, loc=one.loc())))
  }
  Some(@syntax.Pattern::Array(pats=Closed(@list.List(pats)), loc=expr.loc()))
}

///|
/// A hole where a pattern stands takes a name or a string: `$case => ...` with a
/// name stands for a constructor, a binding or another pattern, with a string it
/// matches that text, and with an array of literals it matches the elements. A
/// match the generator writes arm by arm needs all three.
impl @syntax.MapVisitor for Splicer with fn visit_Pattern_Var(self, binder) {
  if self.ones.get(binder.name) is Some((hole, body)) {
    match body {
      Name(n) => return Var({ ..binder, name: n, })
      Text(t) => return Constant(c=String(escape(t)), loc=binder.loc)
      Expr(w) =>
        match expr_of(w) {
          Constant(c~, ..) => return Constant(c~, loc=binder.loc)
          array =>
            match constant_array(array) {
              Some(pattern) => return pattern
              None =>
                self.misfit(
                  hole, "a name, a string, a literal, or an array of literals in a pattern",
                )
            }
        }
      _ =>
        self.misfit(
          hole, "a name, a string, a literal, or an array of literals in a pattern",
        )
    }
  }
  Var(@syntax.MapVisitor::visit_Binder(self, binder))
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
  let items = self.expand(@list.List(given)).to_array()
  let visited = items.map(e => @syntax.MapVisitor::visit_Expr(self, e))
  chain(visited[:], Unit(loc~, faked=true))
}

///|
/// A run of statements as one expression. A `let` binds the rest of its block, so
/// the run folds from the right; one that ends in a `let` binds a unit, which is
/// how the parser writes `let x = 1` on its own.
fn chain(items : ArrayView[@syntax.Expr], base : @syntax.Expr) -> @syntax.Expr {
  let plain = []
  let mut i = 0
  while i < items.length() && !binds(items[i]) {
    plain.push(items[i])
    i = i + 1
  }
  if i == items.length() {
    guard plain.pop() is Some(last) else { return base }
    guard !plain.is_empty() else { return last }
    return Sequence(exprs=@list.List(plain), last_expr=last, loc=base.loc())
  }
  let tail = bind(items[i], chain(items[i + 1:], base))
  guard !plain.is_empty() else { return tail }
  Sequence(exprs=@list.List(plain), last_expr=tail, loc=base.loc())
}

///|
/// Whether an expression introduces a binding, and so takes the rest of its block
/// as its body.
fn binds(expr : @syntax.Expr) -> Bool {
  match expr {
    Let(body=Unit(..), ..) | LetMut(body=Unit(..), ..) => true
    _ => false
  }
}

///|
/// `head` with `tail` as the body it binds.
fn bind(head : @syntax.Expr, tail : @syntax.Expr) -> @syntax.Expr {
  match head {
    Let(pattern~, expr~, ..) => Let(pattern~, expr~, body=tail, loc=head.loc())
    LetMut(binder~, ty~, expr~, ..) =>
      LetMut(binder~, ty~, expr~, body=tail, loc=head.loc())
    _ => head
  }
}

///|
impl @syntax.MapVisitor for Splicer with fn visit_Expr_Apply(
  self,
  func~,
  args~,
  loc~,
) {
  @syntax.MapVisitor::visit_Expr_Apply(
    @syntax.MapVisitorBase(self),
    func~,
    args=self.expand_arguments(args),
    loc~,
  )
}

///|
/// A lone placeholder where a field stands is a punned field, `{ $fields* }` is
/// `{ moonast__fields }`; that one field is where the list goes.
fn Splicer::field_hole(self : Splicer, field : @syntax.FieldDef) -> String? {
  guard field.expr is Ident(id={ name: Ident(name~), .. }, ..) else {
    return None
  }
  guard field.label.name == name && self.manys.contains(name) else {
    return None
  }
  Some(name)
}

///|
/// A list of fields, expanded where a record's field list goes.
fn Splicer::expand_fields(
  self : Splicer,
  fields : @list.List[@syntax.FieldDef],
) -> @list.List[@syntax.FieldDef] {
  let out = []
  for field in fields {
    match self.field_hole(field) {
      None => out.push(field)
      Some(name) => {
        let (hole, bodies) = self.manys.get(name).unwrap()
        for body in bodies {
          match body {
            Fields(w) =>
              for one in fields_of(w) {
                out.push(one)
              }
            _ => self.misfit(hole, "a list of record fields")
          }
        }
      }
    }
  }
  @list.List(out)
}

///|
impl @syntax.MapVisitor for Splicer with fn visit_Expr_Record(
  self,
  type_name~,
  fields~,
  trailing~,
  loc~,
) {
  @syntax.MapVisitor::visit_Expr_Record(
    @syntax.MapVisitorBase(self),
    type_name~,
    fields=self.expand_fields(fields),
    trailing~,
    loc~,
  )
}

///|
impl @syntax.MapVisitor for Splicer with fn visit_Expr_RecordUpdate(
  self,
  type_name~,
  record~,
  fields~,
  loc~,
) {
  @syntax.MapVisitor::visit_Expr_RecordUpdate(
    @syntax.MapVisitorBase(self),
    type_name~,
    record~,
    fields=self.expand_fields(fields),
    loc~,
  )
}

///|
/// The placeholder a case list stands as: a case is never written without a body,
/// so the hole takes `$cases* => ()` and the `()` goes with it.
fn Splicer::case_hole(self : Splicer, case_ : @syntax.Case) -> String? {
  guard case_.pattern is Var(binder) else { return None }
  guard self.manys.get(binder.name) is Some((hole, _)) else { return None }
  guard case_.guard_ is None && case_.body is Unit(..) else {
    self.misfit(hole, "a case list, written `$\{hole}* => ()`")
    return None
  }
  Some(binder.name)
}

///|
impl @syntax.MapVisitor for Splicer with fn visit_Expr_Match(
  self,
  expr~,
  cases~,
  match_loc~,
  loc~,
) {
  let out = []
  for case_ in cases {
    match self.case_hole(case_) {
      None => out.push(case_)
      Some(name) => {
        let (hole, bodies) = self.manys.get(name).unwrap()
        for body in bodies {
          match body {
            Cases(w) =>
              for one in cases_of(w) {
                out.push(one)
              }
            _ => self.misfit(hole, "a list of match cases")
          }
        }
      }
    }
  }
  @syntax.MapVisitor::visit_Expr_Match(
    @syntax.MapVisitorBase(self),
    expr~,
    cases=@list.List(out),
    match_loc~,
    loc~,
  )
}
