///|
/// `#serde.derive(Serialize, Deserialize)` on a type gives it both
/// implementations, written the way the `serde` crate's derive writes them.
struct Derive {}

///|
impl @gen.Generator for Derive with fn name(_) {
  "serde-derive"
}

///|
impl @gen.Generator for Derive with fn generate(_, decls) {
  emit(targets_of(decls))
}

///|
/// With no arguments it reads the bundled declarations, so the example runs as is.
async fn main {
  let args = @env.args()[1:]
  let args = if args.is_empty() {
    [
      "src/examples/serde-derive/fixtures/models.mbt", "-o", "_build/serde.g.mbt",
    ][:]
  } else {
    args
  }
  @cli.run(Derive::{ }, args)
}
