///|
/// What a parameter accepts.
pub(all) enum Kind {
  /// A string literal.
  Str
  /// `true` or `false`.
  Bool
  /// A bare name: `style=plain`, `model=User`.
  Ident
  /// A string holding a MoonBit type: `response="Array[User]"`. A generic or a
  /// qualified type is outside the annotation grammar, so it comes as a string.
  Type
} derive(Eq, Debug)

///|
pub extend Kind with Eq::{equal, not_equal}

///|
pub extend Kind with Debug::{to_repr}

///|
priv struct Param {
  key : String
  kind : Kind
  required : Bool
  positional : Bool
  many : Bool
}

///|
/// The parameters one annotation takes. Built by chaining:
///
/// ```moonbit nocheck
/// Spec::new("app.get").positional("path", Str).optional("summary", Str).many("tags", Str)
/// ```
pub struct Spec {
  priv name : String
  priv params : Array[Param]
}

///|
pub fn Spec::new(name : StringView) -> Spec {
  { name: name.to_owned(), params: [], }
}

///|
fn Spec::add(self : Spec, param : Param) -> Spec {
  let params = self.params.copy()
  params.push(param)
  { ..self, params, }
}

///|
/// A required parameter that may be given by position, in the order these are
/// declared, or by name.
pub fn Spec::positional(self : Spec, key : String, kind : Kind) -> Spec {
  self.add({ key, kind, required: true, positional: true, many: false, })
}

///|
/// A required parameter given by name.
pub fn Spec::required(self : Spec, key : String, kind : Kind) -> Spec {
  self.add({ key, kind, required: true, positional: false, many: false, })
}

///|
/// A parameter that may be left out.
pub fn Spec::optional(self : Spec, key : String, kind : Kind) -> Spec {
  self.add({ key, kind, required: false, positional: false, many: false, })
}

///|
/// A parameter that may be given any number of times, `tags="a", tags="b"`,
/// which is how a list is written where the grammar has no arrays.
pub fn Spec::many(self : Spec, key : String, kind : Kind) -> Spec {
  self.add({ key, kind, required: false, positional: false, many: true, })
}

///|
/// The annotation's arguments, checked against the spec.
///
/// ```mbt check
/// test {
///   let source = "#app.get(\"/users\", tag=\"users\")\nfn list_users() -> Unit {}"
///   let impls = @parser.parse_string(source).0
///   guard impls is @list.More(impl_, tail=@list.Empty) else {
///     abort("one declaration")
///   }
///   guard impl_ is @syntax.TopFuncDef(fun_decl={ attrs, .. }, ..) else {
///     abort("a function")
///   }
///   guard @attr.find(attrs, "app.get") is Some(a) else { abort("annotated") }
///   let spec = @attr.Spec::new("app.get").positional("path", Str).many("tag", Str)
///   let args = spec.bind(a)
///   inspect(args.str("path").unwrap_or(""), content="/users")
///   inspect(args.strs("tag").join(", "), content="users")
/// }
/// ```
pub fn Spec::bind(
  self : Spec,
  attr : @attribute.Attribute,
) -> Args raise Refused {
  let line = attr.loc.start.lnum
  let column = attr.loc.start.column()
  let props = match attr.parsed {
    Some(Apply(_, props)) => props
    Some(Ident(_)) => @list.List([])
    _ => raise Malformed(raw=attr.raw, line~, column~)
  }
  let values : Map[String, Array[Value]] = Map([])
  let positionals = self.params.filter(p => p.positional)
  let mut next = 0
  for prop in props {
    let (param, expr) = match prop {
      Labeled(key, expr) =>
        match self.params.search_by(p => p.key == key) {
          Some(i) => (self.params[i], expr)
          None => raise Unknown(key~, line~, column~)
        }
      Expr(expr) => {
        guard positionals.get(next) is Some(p) else {
          raise Unknown(key="argument \{next + 1}", line~, column~)
        }
        next = next + 1
        (p, expr)
      }
    }
    let value = read(param, expr, line, column)
    let seen = values.get_or_init(param.key, () => [])
    if seen.length() > 0 && !param.many {
      raise Repeated(key=param.key, line~, column~)
    }
    seen.push(value)
  }
  for param in self.params {
    if param.required && !values.contains(param.key) {
      raise Missing(key=param.key, line~, column~)
    }
  }
  { name: self.name, values, line, column, }
}

///|
fn read(
  param : Param,
  expr : @attribute.Expr,
  line : Int32,
  column : Int32,
) -> Value raise Refused {
  match (param.kind, expr) {
    (Str, String(s)) => Str(s)
    (Bool, Bool(b)) => Bool(b)
    (Ident, Ident({ qual: None, name, })) => Ident(name)
    (Type, String(s)) if is_type(s) => Type(s)
    _ =>
      raise Mistyped(
        key=param.key,
        expected=match param.kind {
          Str => "a string"
          Bool => "true or false"
          Ident => "a name"
          Type => "a string holding a type"
        },
        line~,
        column~,
      )
  }
}

///|
/// Whether `source` parses as a MoonBit type.
fn is_type(source : String) -> Bool {
  let (_, reports) = @parser.parse_string(
    "fn moonast__type(x : " + source + ") -> Unit {\n  ()\n}",
  )
  reports.length() == 0
}
