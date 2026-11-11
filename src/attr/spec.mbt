///|
/// What a parameter accepts.
#derive(Eq, Debug)
pub(all) enum Kind {
  /// A string literal.
  Str
  /// `true` or `false`.
  Bool
  /// A bare name: `style=plain`, `model=User`.
  Ident
  /// A name with one qualifier, `contract=Registry.users`, which is how a value
  /// in another namespace is written. The parser also takes `@pkg.name`, but what
  /// it gives back keeps the qualifier alone, so `@pkg.name` and `pkg.name` read
  /// alike, as `pkg.name`; a name whose `@` matters is passed as a string.
  Path
  /// A string holding a MoonBit type: `response="Array[User]"`. A generic or a
  /// qualified type is outside the annotation grammar, so it comes as a string.
  Type
}

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
/// A parameter that may be given by position, in the order these are declared, or by name. It is
/// required unless `optional` says otherwise, which is what lets `#orm.table("heroes")` and a bare
/// `#orm.table` both stand.
pub fn Spec::positional(
  self : Spec,
  key : String,
  kind : Kind,
  optional~ : Bool = false,
) -> Spec {
  self.add({ key, kind, required: !optional, positional: true, many: false, })
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
/// A parameter that may be given any number of times, `tags="a", tags="b"`, or
/// `tags=["a", "b"]`, whose elements count the same way. With `positional`, the list
/// is written as bare arguments, `#serde.derive(Serialize, Deserialize)`, and it
/// takes every one of them from where it starts.
pub fn Spec::many(
  self : Spec,
  key : String,
  kind : Kind,
  positional~ : Bool = false,
) -> Spec {
  self.add({ key, kind, required: false, positional, many: true, })
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
///
/// Pass the file the annotation was read from and every refusal names it, so the
/// line and column in the message can be opened:
///
/// ```mbt check
/// test {
///   let source = "#app.get\nfn list_users() -> Unit {}"
///   let impls = @parser.parse_string(source).0
///   guard impls is @list.More(impl_, tail=@list.Empty) else {
///     abort("one declaration")
///   }
///   guard impl_ is @syntax.TopFuncDef(fun_decl={ attrs, .. }, ..) else {
///     abort("a function")
///   }
///   guard @attr.find(attrs, "app.get") is Some(a) else { abort("annotated") }
///   let refused = try {
///     let _ = @attr.Spec::new("app.get")
///       .positional("path", Str)
///       .bind(a, file="models.mbt")
///     "bound"
///   } catch {
///     e => e.to_string()
///   }
///   inspect(refused, content="models.mbt:1:1: path is required")
/// }
/// ```
pub fn Spec::bind(
  self : Spec,
  attr : @attribute.Attribute,
  file~ : String = "",
) -> Args raise Refused {
  let line = attr.loc.start.lnum
  let column = attr.loc.start.column()
  let props = match attr.parsed {
    Some(Apply(_, props)) => props
    Some(Ident(_)) => @list.List([])
    _ => raise Malformed(raw=attr.raw, line~, column~, file~)
  }
  let values : Map[String, Array[Value]] = Map([])
  let positionals = self.params.filter(p => p.positional)
  let mut next = 0
  for prop in props {
    let (param, expr) = match prop {
      Labeled(key, expr) =>
        match self.params.search_by(p => p.key == key) {
          Some(i) => (self.params[i], expr)
          None => raise Unknown(key~, line~, column~, file~)
        }
      Expr(expr) => {
        // A positional that may repeat keeps taking arguments; the ones before
        // it are used up one at a time.
        let taken = if next < positionals.length() {
          positionals[next]
        } else {
          match positionals.search_by(p => p.many) {
            Some(i) => positionals[i]
            None =>
              raise Unknown(key="argument \{next + 1}", line~, column~, file~)
          }
        }
        if !taken.many {
          next = next + 1
        }
        (taken, expr)
      }
    }
    // An array is the list a repeated key writes, written once: `tags=["a", "b"]`
    // says what `tags="a", tags="b"` says, element by element read the same way.
    // Repeating stays the spec's to allow, so a second value for a parameter that
    // takes one is still a repetition, whether it came from an array or a key.
    let exprs = match expr {
      Array(elems) => elems
      _ => @list.singleton(expr)
    }
    for one in exprs {
      let value = read(param, one, line, column, file)
      let seen = values.get_or_init(param.key, () => [])
      if seen.length() > 0 && !param.many {
        raise Repeated(key=param.key, line~, column~, file~)
      }
      seen.push(value)
    }
  }
  for param in self.params {
    if param.required && !values.contains(param.key) {
      raise Missing(key=param.key, line~, column~, file~)
    }
  }
  { name: self.name, values, line, column, file, }
}

///|
fn read(
  param : Param,
  expr : @attribute.Expr,
  line : Int32,
  column : Int32,
  file : String,
) -> Value raise Refused {
  match (param.kind, expr) {
    (Str, String(s)) => Str(decoded(s))
    (Bool, Bool(b)) => Bool(b)
    (Ident, Ident({ qual: None, name, })) => Ident(name)
    (Path, Ident({ qual: Some(q), name, })) => Ident(q + "." + name)
    (Path, Ident({ qual: None, name, })) => Ident(name)
    (Type, String(s)) if is_type(s) => Type(s)
    _ =>
      raise Mistyped(
        key=param.key,
        expected=match param.kind {
          Str => "a string"
          Bool => "true or false"
          Ident => "a name"
          Path => "a name, or a name after a qualifier"
          Type => "a string holding a type"
        },
        line~,
        column~,
        file~,
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
