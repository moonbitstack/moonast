///|
/// One argument, as its kind reads it.
pub(all) enum Value {
  Str(String)
  Bool(Bool)
  Ident(String)
  Type(String)
} derive(Eq, Debug)

///|
pub extend Value with Eq::{equal, not_equal}

///|
pub extend Value with Debug::{to_repr}

///|
/// An annotation's arguments after `Spec::bind`: every required one is here and
/// every one has the kind its spec gives.
pub struct Args {
  name : String
  priv values : Map[String, Array[Value]]
  line : Int32
  column : Int32
}

///|
/// The values given for `key`, in order; empty when it was not given.
pub fn Args::get(self : Args, key : StringView) -> Array[Value] {
  self.values.get(key.to_owned()).unwrap_or([])
}

///|
/// Whether `key` was given.
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
///   let args = @attr.Spec::new("app.get")
///     .positional("path", Str)
///     .many("tag", Str)
///     .bind(a)
///   inspect(args.has("tag"), content="true")
///   inspect(args.has("page"), content="false")
/// }
/// ```
pub fn Args::has(self : Args, key : StringView) -> Bool {
  self.values.contains(key.to_owned())
}

///|
/// The string given for `key`.
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
///   let args = @attr.Spec::new("app.get")
///     .positional("path", Str)
///     .many("tag", Str)
///     .bind(a)
///   inspect(args.str("path").unwrap_or(""), content="/users")
/// }
/// ```
pub fn Args::str(self : Args, key : StringView) -> String? {
  match self.get(key) {
    [Str(s), ..] | [Type(s), ..] | [Ident(s), ..] => Some(s)
    _ => None
  }
}

///|
/// Every string given for a repeated `key`.
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
///   let args = @attr.Spec::new("app.get")
///     .positional("path", Str)
///     .many("tag", Str)
///     .bind(a)
///   inspect(args.strs("tag").join(", "), content="users")
/// }
/// ```
pub fn Args::strs(self : Args, key : StringView) -> Array[String] {
  self
  .get(key)
  .filter_map(v => {
    match v {
      Str(s) | Type(s) | Ident(s) => Some(s)
      Bool(_) => None
    }
  })
}

///|
/// The boolean given for `key`.
pub fn Args::bool(self : Args, key : StringView) -> Bool? {
  match self.get(key) {
    [Bool(b), ..] => Some(b)
    _ => None
  }
}
