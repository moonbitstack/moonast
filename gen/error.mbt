///|
/// Why a generator's inputs were not read.
pub(all) suberror Refused {
  /// An input file is not MoonBit.
  Syntax(file~ : String, line~ : Int32, column~ : Int32, msg~ : String)
} derive(Debug)

///|
pub extend Refused with Debug::{to_repr}

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Syntax(file~, line~, column~, msg~) =>
      logger.write_string("\{file}:\{line}:\{column}: \{msg}")
  }
}

///|
pub extend Refused with Show::{to_string, output}
