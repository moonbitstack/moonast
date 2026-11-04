///|
/// Why a generator run stopped.
#derive(Debug)
pub(all) suberror Refused {
  /// The command line is not `[-C <dir>] <inputs...> -o <output> [--check]`.
  Usage(msg~ : String)
  /// `--check` found the output out of date with its inputs.
  Stale(output~ : String)
  /// The generator refused what it read, in its own words.
  Generator(msg~ : String)
}

///|
pub extend Refused with Debug::{to_repr}

///|
pub impl Show for Refused with fn output(self, logger) {
  let text = match self {
    Usage(msg~) => "\{msg}; usage: [-C <dir>] <inputs...> -o <output> [--check]"
    Stale(output~) =>
      "\{output} is out of date with its inputs; run the generator again"
    Generator(msg~) => msg
  }
  logger.write_string(text)
}

///|
pub extend Refused with Show::{to_string, output}

///|
priv struct Plan {
  inputs : Array[String]
  output : String
  check : Bool
}

///|
/// `path` against `dir` unless it is already absolute. A dev_build rule runs the
/// generator from elsewhere (`moon -C`), so it passes the module directory as
/// `-C "$mod_dir"` and the paths moon gives it stay relative to that.
fn resolve(dir : String?, path : String) -> String {
  let absolute = path.has_prefix("/") ||
    path.has_prefix("\\") ||
    (path.length() > 1 && path.get_char(1) is Some(':'))
  match dir {
    Some(d) if !absolute => d + "/" + path
    _ => path
  }
}

///|
fn plan(args : ArrayView[String]) -> Plan raise Refused {
  let inputs = []
  let mut output = None
  let mut check = false
  let mut dir = None
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "-o" => {
        guard args.get(i + 1) is Some(path) else {
          raise Usage(msg="-o needs a path")
        }
        guard output is None else { raise Usage(msg="-o is given twice") }
        output = Some(path)
        i = i + 2
        continue
      }
      "-C" => {
        guard args.get(i + 1) is Some(path) else {
          raise Usage(msg="-C needs a directory")
        }
        dir = Some(path)
        i = i + 2
        continue
      }
      "--check" => check = true
      arg if arg.has_prefix("-") => raise Usage(msg="there is no option \{arg}")
      arg => inputs.push(arg)
    }
    i = i + 1
  }
  guard output is Some(output) else { raise Usage(msg="-o is required") }
  guard inputs.length() > 0 else { raise Usage(msg="no input files") }
  {
    inputs: inputs.map(p => resolve(dir, p)),
    output: resolve(dir, output),
    check,
  }
}

///|
/// What a generator said with `fail`, without the place in the generator's own source that `fail`
/// puts in front of it. The sentence already names the place in the user's.
fn sentence(msg : String) -> String {
  let mark = "FAILED: "
  match msg.find(mark) {
    Some(at) => msg[at + mark.length():].to_owned()
    None => msg
  }
}

///|
/// Run `generator` the way a dev_build rule calls it: read every input, render
/// them, and write the output; with `--check`, only compare and refuse when the
/// output is stale. `args` are the arguments after the program name; `-C <dir>`
/// makes relative paths relative to `dir`.
pub async fn run(generator : &@gen.Generator, args : ArrayView[String]) -> Unit {
  let plan = plan(args)
  let sources = []
  for path in plan.inputs {
    sources.push((path, @fs.read_file(path).text()))
  }
  let rendered = @gen.render(generator, sources) catch {
    Failure(msg) => raise Generator(msg=sentence(msg))
    e => raise e
  }
  if plan.check {
    let current = if @fs.exists(plan.output) {
      @fs.read_file(plan.output).text()
    } else {
      ""
    }
    // A checkout that turned line feeds into CRLF has not changed the code.
    let lf = (s : String) => s.replace_all(old="\r\n", new="\n")
    guard lf(current) == lf(rendered) else { raise Stale(output=plan.output) }
  } else {
    @fs.write_file(plan.output, rendered)
  }
}
