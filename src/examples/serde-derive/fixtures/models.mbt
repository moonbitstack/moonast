// Types whose implementations are generated, not written.
//
// Run `moonx moonbit-community/serde.mbt/derive example` (or, inside this repo,
// `moon run derive -- example`) to regenerate `types_derive.mbt` after
// changing anything here.

///|
#derive(Eq, Debug)
#serde.derive(Serialize, Deserialize)
pub(all) struct Point {
  x : Int32
  y : Int32
  /// An `Option` field: absent and explicitly null both read back as `None`.
  label : String?
}

///|
#derive(Eq, Debug)
#serde.derive(Serialize, Deserialize)
pub(all) struct Config {
  /// The wire name need not be a legal MoonBit identifier.
  #serde.rename("max-retries")
  max_retries : Int32
  /// Never written, and filled from `Default` on the way back in.
  #serde.skip
  cache_generation : Int32
}

///|
#derive(Eq, Debug)
#serde.derive(Serialize, Deserialize)
pub(all) enum Shape {
  Empty
  Circle(Double)
  Rect(Double, Double)
  Tagged(name~ : String, size~ : Int32)
  #serde.rename("Ellipse")
  Oval(Double, Double)
}

///|
#derive(Eq, Debug)
#serde.derive(Serialize, Deserialize)
pub(all) struct Pair[A, B] {
  first : A
  second : B
}

///|
#derive(Eq, Debug)
#serde.derive(Serialize, Deserialize)
pub(all) struct Rgb(Int32, Int32, Int32)

///|
/// One positional field is a wrapper, not a tuple of one: it is written as the
/// value it wraps, and the name survives only for formats that record it.
#derive(Eq, Debug)
#serde.derive(Serialize, Deserialize)
pub(all) struct Meters(Double)

///|
/// Nothing to write, so it goes out as unit.
#derive(Eq, Debug)
#serde.derive(Serialize, Deserialize)
pub(all) struct Marker {}
