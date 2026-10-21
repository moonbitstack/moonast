///|
/// Why a template or a code was not accepted. Each variant is named after the
/// thing that was wrong.
pub(all) suberror Refused {
  /// The template is not MoonBit once its holes are in place.
  Template(msg~ : String, line~ : Int32, column~ : Int32)
  /// A hole in the template was given nothing.
  Unfilled(hole~ : String)
  /// Something was given for a hole the template does not have.
  Unused(hole~ : String)
  /// A hole was given a code of the wrong kind for where it stands.
  Misfit(hole~ : String, expected~ : String)
  /// `ident` was given something that is not an identifier.
  Name(name~ : String)
  /// `join` was given a code that is not declarations.
  Kind(expected~ : String)
} derive(Debug)

///|
pub extend Refused with Debug::{to_repr}

///|
pub impl Show for Refused with fn output(self, logger) {
  let text = match self {
    Template(msg~, line~, column~) =>
      "the template is not MoonBit at \{line}:\{column}: \{msg}"
    Unfilled(hole~) => "hole $\{hole} was given nothing"
    Unused(hole~) => "the template has no hole $\{hole}"
    Misfit(hole~, expected~) => "hole $\{hole} takes \{expected}"
    Name(name~) => "\{name} is not an identifier"
    Kind(expected~) => "expected \{expected}"
  }
  logger.write_string(text)
}

///|
pub extend Refused with Show::{to_string, output}
