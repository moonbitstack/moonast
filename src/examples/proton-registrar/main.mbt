///|
/// `#proton.command(contract=...)` on a function puts it in the package's
/// `register_commands`, and a method command goes in its type's.
struct Registrar {}

///|
impl @gen.Generator for Registrar with fn name(_) {
  "proton-registrar"
}

///|
impl @gen.Generator for Registrar with fn generate(_, decls) {
  emit(commands_of(decls))
}

///|
/// With no arguments it reads the bundled declarations, so the example runs as is.
async fn main {
  let args = @env.args()[1:]
  let args = if args.is_empty() {
    [
      "src/examples/proton-registrar/fixtures/commands.mbt", "-o", "_build/commands.g.mbt",
    ][:]
  } else {
    args
  }
  @cli.run(Registrar::{ }, args)
}
