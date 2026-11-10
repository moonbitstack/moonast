///|
/// Why an annotation's arguments were not accepted, with where the annotation
/// stands in its file. `file` is empty when the caller did not say which file it
/// read the annotation from, and then the message names the position alone.
#derive(Debug)
pub(all) suberror Refused {
  /// The payload is outside the annotation grammar: arrays, numbers, a qualified
  /// or generic type cannot be written, and a keyword cannot be a label.
  Malformed(raw~ : String, line~ : Int32, column~ : Int32, file~ : String)
  /// A required parameter was not given.
  Missing(key~ : String, line~ : Int32, column~ : Int32, file~ : String)
  /// A parameter the spec does not have.
  Unknown(key~ : String, line~ : Int32, column~ : Int32, file~ : String)
  /// A parameter of the wrong kind.
  Mistyped(
    key~ : String,
    expected~ : String,
    line~ : Int32,
    column~ : Int32,
    file~ : String
  )
  /// A parameter given twice that may only be given once.
  Repeated(key~ : String, line~ : Int32, column~ : Int32, file~ : String)
}

///|
pub extend Refused with Debug::{to_repr}

///|
pub impl Show for Refused with fn output(self, logger) {
  let (file, line, column, text) = match self {
    Malformed(raw~, line~, column~, file~) =>
      (file, line, column, "cannot read the arguments of \{raw}")
    Missing(key~, line~, column~, file~) =>
      (file, line, column, "\{key} is required")
    Unknown(key~, line~, column~, file~) =>
      (file, line, column, "there is no \{key}")
    Mistyped(key~, expected~, line~, column~, file~) =>
      (file, line, column, "\{key} takes \{expected}")
    Repeated(key~, line~, column~, file~) =>
      (file, line, column, "\{key} is given more than once")
  }
  let at = if file == "" {
    "\{line}:\{column}"
  } else {
    "\{file}:\{line}:\{column}"
  }
  logger.write_string("\{at}: \{text}")
}

///|
pub extend Refused with Show::{to_string, output}
