///|
/// The generator the guide's command-line section runs.
struct GuideNames {}

///|
impl @gen.Generator for GuideNames with fn name(_) {
  "describe"
}

///|
impl @gen.Generator for GuideNames with fn generate(_, decls) {
  let names = decls.filter_map(decl => {
    match decl {
      Struct(name~, ..) => Some(@quote.string(name))
      _ => None
    }
  })
  @quote.items("fn struct_names() -> Array[String] { [$names*] }")
  .splice("names", names)
  .render()
}

///|
/// The command line the guide prints after each refusal.
let usage : String = "; usage: [-C <dir>] <inputs...> -o <output> [--check]"

///|
async test "the two usage lines the guide prints" {
  let messages = []
  for args in [["models.mbt"], ["-o", "describe.g.mbt"]] {
    let text = try {
      @cli.run(GuideNames::{ }, args)
      "ran"
    } catch {
      e => e.to_string()
    }
    messages.push(text)
  }
  inspect(messages[0], content="-o is required" + usage)
  inspect(messages[1], content="no input files" + usage)
}

///|
async test "a stale output is reported in the words the guide prints" {
  let dir = @fs.tmpdir(prefix="moonast-guide")
  defer @fs.rmdir(dir, recursive=true)
  let input = dir + "/models.mbt"
  let output = dir + "/describe.g.mbt"
  @fs.write_file(input, "struct Point {\n  x : Int\n}\n")
  @cli.run(GuideNames::{ }, [input, "-o", output])
  // Somebody edited the generated file by hand.
  @fs.write_file(output, @fs.read_file(output).text() + "\n// a hand edit\n")
  let stale = try {
    @cli.run(GuideNames::{ }, [input, "-o", output, "--check"])
    "checked"
  } catch {
    e => e.to_string()
  }
  inspect(
    stale.contains(
      "describe.g.mbt is out of date with its inputs; run the generator again",
    ),
    content="true",
  )
}
