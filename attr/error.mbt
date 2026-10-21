///|
/// Why an annotation's arguments were not accepted, with where the annotation
/// stands in its file.
pub(all) suberror Refused {
  /// moonbitlang/parser could not read the payload: arrays, numbers, a qualified
  /// or generic type, and a keyword used as a label (`method`, `type`) are outside
  /// the annotation grammar.
  Malformed(raw~ : String, line~ : Int32, column~ : Int32)
  /// A required parameter was not given.
  Missing(key~ : String, line~ : Int32, column~ : Int32)
  /// A parameter the spec does not have.
  Unknown(key~ : String, line~ : Int32, column~ : Int32)
  /// A parameter of the wrong kind.
  Mistyped(key~ : String, expected~ : String, line~ : Int32, column~ : Int32)
  /// A parameter given twice that may only be given once.
  Repeated(key~ : String, line~ : Int32, column~ : Int32)
} derive(Debug)

///|
pub extend Refused with Debug::{to_repr}

///|
pub impl Show for Refused with fn output(self, logger) {
  let text = match self {
    Malformed(raw~, line~, column~) =>
      "\{line}:\{column}: cannot read the arguments of \{raw}"
    Missing(key~, line~, column~) => "\{line}:\{column}: \{key} is required"
    Unknown(key~, line~, column~) => "\{line}:\{column}: there is no \{key}"
    Mistyped(key~, expected~, line~, column~) =>
      "\{line}:\{column}: \{key} takes \{expected}"
    Repeated(key~, line~, column~) =>
      "\{line}:\{column}: \{key} is given more than once"
  }
  logger.write_string(text)
}

///|
pub extend Refused with Show::{to_string, output}
