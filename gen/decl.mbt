///|
/// A field of a struct, with its type as written in the source.
pub(all) struct Field {
  name : String
  ty : String
  mutable : Bool
  attrs : @list.List[@attribute.Attribute]
}

///|
/// How a function parameter is passed.
pub(all) enum Pass {
  Positional
  Labelled
  Optional
  Defaulted
} derive(Eq, Debug)

///|
pub extend Pass with Eq::{equal, not_equal}

///|
pub extend Pass with Debug::{to_repr}

///|
/// A function parameter: `_` has no name, and an unannotated one no type.
pub(all) struct Param {
  name : String?
  ty : String?
  pass : Pass
}

///|
/// A top-level declaration as a generator usually needs it. Types are kept as
/// their source text, which is what a generator splices into new code; `raw` is
/// the official syntax tree for anything the view leaves out.
pub(all) enum Decl {
  Struct(
    name~ : String,
    fields~ : Array[Field],
    attrs~ : @list.List[@attribute.Attribute],
    public~ : Bool,
    file~ : String,
    raw~ : @syntax.Impl
  )
  Enum(
    name~ : String,
    constructors~ : Array[String],
    attrs~ : @list.List[@attribute.Attribute],
    public~ : Bool,
    file~ : String,
    raw~ : @syntax.Impl
  )
  Func(
    owner~ : String?,
    name~ : String,
    params~ : Array[Param],
    returns~ : String?,
    is_async~ : Bool,
    attrs~ : @list.List[@attribute.Attribute],
    public~ : Bool,
    file~ : String,
    raw~ : @syntax.Impl
  )
  Other(file~ : String, raw~ : @syntax.Impl)
}

///|
/// The annotations on a declaration; none for `Other`.
pub fn Decl::attrs(self : Decl) -> @list.List[@attribute.Attribute] {
  match self {
    Struct(attrs~, ..) | Enum(attrs~, ..) | Func(attrs~, ..) => attrs
    Other(..) => @list.List([])
  }
}

///|
/// The official syntax tree behind the view.
pub fn Decl::raw(self : Decl) -> @syntax.Impl {
  match self {
    Struct(raw~, ..) | Enum(raw~, ..) | Func(raw~, ..) | Other(raw~, ..) => raw
  }
}

///|
fn visible(vis : @syntax.Visibility) -> Bool {
  vis is Pub(..)
}

///|
/// The source text a type covers.
fn text(source : String, t : @syntax.Type) -> String {
  let loc = t.loc()
  let start = loc.start.cnum
  let end = loc.end.cnum
  guard 0 <= start && start <= end && end <= source.length() else { return "" }
  source[start:end].to_owned()
}

///|
fn view(source : String, file : String, impl_ : @syntax.Impl) -> Decl {
  match impl_ {
    TopTypeDef(decl) =>
      match decl.components {
        Record(fields~, ..) =>
          Struct(
            name=decl.tycon,
            fields=fields
              .iter()
              .map(f => {
                name: f.name.label,
                ty: text(source, f.ty),
                mutable: f.mut_,
                attrs: f.attrs,
              })
              .collect(),
            attrs=decl.attrs,
            public=visible(decl.type_vis),
            file~,
            raw=impl_,
          )
        Variant(constrs) =>
          Enum(
            name=decl.tycon,
            constructors=constrs.iter().map(c => c.name.name).collect(),
            attrs=decl.attrs,
            public=visible(decl.type_vis),
            file~,
            raw=impl_,
          )
        _ => Other(file~, raw=impl_)
      }
    TopFuncDef(fun_decl~, ..) =>
      Func(
        owner=fun_decl.type_name.map(t => long_name(t.name)),
        name=fun_decl.name.name,
        params=match fun_decl.decl_params {
          Some(params) => params.iter().map(p => param(source, p)).collect()
          None => []
        },
        returns=fun_decl.return_type.map(t => text(source, t)),
        is_async=fun_decl.is_async is Some(_),
        attrs=fun_decl.attrs,
        public=visible(fun_decl.vis),
        file~,
        raw=impl_,
      )
    _ => Other(file~, raw=impl_)
  }
}

///|
fn long_name(id : @syntax.LongIdent) -> String {
  match id {
    Ident(name~) => name
    Dot(pkg~, id~) => "@" + pkg + "." + id
  }
}

///|
fn param(source : String, p : @syntax.Parameter) -> Param {
  let ty = (t : @syntax.Type?) => t.map(t => text(source, t))
  match p {
    DiscardPositional(ty=t, ..) => { name: None, ty: ty(t), pass: Positional, }
    Positional(binder~, ty=t) =>
      { name: Some(binder.name), ty: ty(t), pass: Positional, }
    Labelled(binder~, ty=t) =>
      { name: Some(binder.name), ty: ty(t), pass: Labelled, }
    Optional(binder~, ty=t, ..) =>
      { name: Some(binder.name), ty: ty(t), pass: Defaulted, }
    QuestionOptional(binder~, ty=t) =>
      { name: Some(binder.name), ty: ty(t), pass: Optional, }
  }
}

///|
/// The declarations of one file, in source order. Refused when the file is not
/// MoonBit, with the first problem's position.
pub fn read(file : String, source : String) -> Array[Decl] raise Refused {
  let (impls, reports) = @parser.parse_string(source, name=file)
  if reports.get(0) is Some(r) {
    raise Syntax(
      file~,
      line=r.loc.start.lnum,
      column=r.loc.start.column(),
      msg=r.msg,
    )
  }
  impls.iter().map(i => view(source, file, i)).collect()
}
