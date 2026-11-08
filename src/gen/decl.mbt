///|
/// A field of a struct, with its type as written in the source.
#derive(Debug)
pub(all) struct Field {
  name : String
  ty : String
  mutable : Bool
  /// Whether the declared type is `Option`, written `T?` or `Option[T]`. A
  /// generator that treats an absent value differently from a present one needs
  /// this, and reading it off the type text gets it wrong: `T?` is sugar for the
  /// same type as `Option[T]`, and neither is the text `Option`.
  optional : Bool
  attrs : @list.List[@attribute.Attribute]
}

///|
pub extend Field with Debug::{to_repr}

///|
/// How a function parameter is passed.
#derive(Eq, Debug)
pub(all) enum Pass {
  Positional
  Labelled
  Optional
  Defaulted
}

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
/// The body of a type declaration: what a struct is made of, or the cases an
/// enum has. One type for both, because a variant carries the same three shapes a
/// struct can have — nothing, a run of positional types, or named fields.
///
/// ```mbt check
/// test {
///   let source =
///     #|pub enum Shape {
///     #|  Empty
///     #|  Circle(Double)
///     #|  Rect(Double, Double)
///     #|  Tagged(name~ : String, size~ : Int)
///     #|}
///   guard @gen.read("m.mbt", source) is [Enum(cases~, ..)] else {
///     abort("an enum")
///   }
///   let shapes = cases.map(c => {
///     match c.payload {
///       Empty => "empty"
///       Tuple(arity~) => "tuple of \{arity}"
///       Record(fields~) => "record of \{fields.length()}"
///       _ => "cases"
///     }
///   })
///   inspect(
///     shapes.join(", "),
///     content="empty, tuple of 1, tuple of 2, record of 2",
///   )
/// }
/// ```
#derive(Debug)
pub(all) enum Shape {
  /// `struct Marker {}`, or a variant with nothing in it.
  Empty
  /// `struct Rgb(Int, Int, Int)`, or `Circle(Double)`: a newtype when the count
  /// is one. A generator that writes `self.0` and `self.1` needs the count and
  /// nothing else; one that needs the types reads them off `Decl::raw`.
  Tuple(arity~ : Int32)
  /// `struct Point { x : Int }`, or `Tagged(name~ : String)`: the fields, with
  /// their types as written in the source.
  Record(fields~ : Array[Field])
  /// `enum Shape { ... }`: its variants, in source order.
  Cases(cases~ : Array[Case])
}

///|
pub extend Shape with Debug::{to_repr}

///|
/// One variant of an enum, and the annotations written on it. Its `payload` is
/// `Empty`, `Tuple` or `Record`; an enum inside an enum's variant would be a
/// different type altogether, so `Cases` never appears here.
#derive(Debug)
pub(all) struct Case {
  name : String
  payload : Shape
  attrs : @list.List[@attribute.Attribute]
}

///|
pub extend Case with Debug::{to_repr}

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
    cases~ : Array[Case],
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
  /// Anything else, with the annotations on it: a tuple struct is here, since
  /// `Struct` covers the record case only, and so is an `impl` or a `trait`.
  Other(
    file~ : String,
    attrs~ : @list.List[@attribute.Attribute],
    raw~ : @syntax.Impl
  )
}

///|
/// The annotations on a declaration, whatever the view makes of its body.
///
/// ```mbt check
/// test {
///   let source = "#demo.describe\npub struct Point {\n  x : Int\n}"
///   guard @gen.read("models.mbt", source) is [decl] else {
///     abort("one declaration")
///   }
///   inspect(@attr.find(decl.attrs(), "demo.describe") is Some(_), content="true")
/// }
/// ```
pub fn Decl::attrs(self : Decl) -> @list.List[@attribute.Attribute] {
  match self {
    Struct(attrs~, ..)
    | Enum(attrs~, ..)
    | Func(attrs~, ..)
    | Other(attrs~, ..) => attrs
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
/// The name a declaration introduces: a type's or a function's. Empty for one that
/// introduces none, such as an `impl`. A tuple struct has no variant of its own, so
/// this is how a generator learns its name without reading `raw` itself.
///
/// ```mbt check
/// test {
///   let source = "pub struct Rgb(Int, Int, Int)\n\npub fn f() -> Unit { () }"
///   let names = @gen.read("m.mbt", source).map(decl => decl.name())
///   inspect(names.join(", "), content="Rgb, f")
/// }
/// ```
pub fn Decl::name(self : Decl) -> String {
  match self {
    Struct(name~, ..) | Enum(name~, ..) | Func(name~, ..) => name
    Other(..) =>
      match self.raw() {
        TopTypeDef(decl) => decl.tycon
        _ => ""
      }
  }
}

///|
/// Whether the declaration is `pub`, for every kind the view has a variant for
/// and for the tuple structs that land in `Other`.
pub fn Decl::is_public(self : Decl) -> Bool {
  match self {
    Struct(public~, ..) | Enum(public~, ..) | Func(public~, ..) => public
    Other(..) =>
      match self.raw() {
        TopTypeDef(decl) => visible(decl.type_vis)
        _ => false
      }
  }
}

///|
/// The body of a type declaration, tuple structs included: `Struct` covers the
/// record case, and this answers the other two. `None` for a function or a
/// declaration that is not a type at all.
///
/// ```mbt check
/// test {
///   let source = "pub struct Rgb(Int, Int, Int)"
///   guard @gen.read("m.mbt", source) is [decl] else { abort("a declaration") }
///   inspect(
///     match decl.shape() {
///       Some(Tuple(arity~)) => "tuple of \{arity}"
///       _ => "not a tuple struct"
///     },
///     content="tuple of 3",
///   )
/// }
/// ```
pub fn Decl::shape(self : Decl) -> Shape? {
  match self {
    Struct(fields~, ..) =>
      Some(if fields.is_empty() { Empty } else { Record(fields~) })
    Enum(cases~, ..) => Some(Cases(cases~))
    _ =>
      match self.raw() {
        TopTypeDef(decl) =>
          match decl.components {
            TupleStruct(types) => Some(Tuple(arity=types.length()))
            _ => None
          }
        _ => None
      }
  }
}

///|
/// The generic parameters of a type declaration, as written: `["A", "B"]` for
/// `struct Pair[A, B]`. Empty for a function, whose own parameters live on `Func`.
///
/// ```mbt check
/// test {
///   guard @gen.read("m.mbt", "pub struct Pair[A, B] {\n  first : A\n}") is [decl] else {
///     abort("a struct")
///   }
///   inspect(decl.params().join(", "), content="A, B")
/// }
/// ```
pub fn Decl::params(self : Decl) -> Array[String] {
  match self.raw() {
    TopTypeDef(decl) => decl.params.iter().filter_map(p => p.name).collect()
    _ => []
  }
}

///|
fn visible(vis : @syntax.Visibility) -> Bool {
  vis is Pub(..)
}

///|
/// Whether a type is `Option`, written either way: `T?` is sugar, and `Option[T]`
/// is the constructor it stands for.
fn is_option(ty : @syntax.Type) -> Bool {
  match ty {
    Option(..) => true
    Name(constr_id={ id: Ident(name="Option"), .. }, tys~, ..) =>
      tys.length() == 1
    _ => false
  }
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
        Record(fields~, ..) => {
          let fields = fields
            .iter()
            .map(f => {
              name: f.name.label,
              ty: text(source, f.ty),
              mutable: f.mut_,
              optional: is_option(f.ty),
              attrs: f.attrs,
            })
            .collect()
          Struct(
            name=decl.tycon,
            fields~,
            attrs=decl.attrs,
            public=visible(decl.type_vis),
            file~,
            raw=impl_,
          )
        }
        Variant(constrs) =>
          Enum(
            name=decl.tycon,
            constructors=constrs.iter().map(c => c.name.name).collect(),
            cases=constrs.iter().map(c => case(source, c)).collect(),
            attrs=decl.attrs,
            public=visible(decl.type_vis),
            file~,
            raw=impl_,
          )
        _ => Other(file~, attrs=decl.attrs, raw=impl_)
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
    _ => Other(file~, attrs=@list.List([]), raw=impl_)
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
/// One variant and the parameters it carries, as the three shapes an enum can
/// have: none, a run of positional types, or named fields.
fn case(source : String, constr : @syntax.ConstrDecl) -> Case {
  let payload = match constr.args {
    None => Empty
    Some(args) if args.is_empty() => Empty
    Some(args) => {
      let named = args.iter().any(p => p.label is Some(_))
      guard named else {
        return {
          name: constr.name.name,
          payload: Tuple(arity=args.length()),
          attrs: constr.attrs,
        }
      }
      Record(
        fields=args
          .iter()
          .filter_map(p => p.label.map(label => (label.name, p.ty)))
          .map(pair => {
            let (name, ty) = pair
            {
              name,
              ty: text(source, ty),
              mutable: false,
              optional: ty is Option(..),
              attrs: @list.List([]),
            }
          })
          .collect(),
      )
    }
  }
  { name: constr.name.name, payload, attrs: constr.attrs, }
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
///
/// ```mbt check
/// test {
///   let source = "pub struct Point {\n  x : Int\n  y : Int\n}"
///   guard @gen.read("models.mbt", source) is [Struct(name~, fields~, ..)] else {
///     abort("a struct")
///   }
///   inspect(name, content="Point")
///   inspect(fields.map(f => f.name).join(", "), content="x, y")
/// }
/// ```
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
