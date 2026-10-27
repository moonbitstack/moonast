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
pub fn Args::has(self : Args, key : StringView) -> Bool {
  self.values.contains(key.to_owned())
}

///|
/// The string given for `key`.
pub fn Args::str(self : Args, key : StringView) -> String? {
  match self.get(key) {
    [Str(s), ..] | [Type(s), ..] | [Ident(s), ..] => Some(s)
    _ => None
  }
}

///|
/// Every string given for a repeated `key`.
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
