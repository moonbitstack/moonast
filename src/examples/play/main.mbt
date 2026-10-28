///|
/// One template, filled and rendered. `kind` is `items`, `expr` or `ty`. Every
/// hole comes as one entry of `fills`, its fields separated by `\u{1F}` and the
/// entries by `\u{1E}`: the hole's name, the kind of code to make from each
/// value, then the values. A hole whose name ends in `*` is spliced.
pub fn template(kind : String, source : String, fills : String) -> String {
  render_of(kind, source, fills) catch {
    e => e.to_string()
  }
}

///|
fn render_of(kind : String, source : String, fills : String) -> String raise {
  let mut tpl : @quote.Template = match kind {
    "expr" => @quote.expr(source)
    "ty" => @quote.ty(source)
    _ => @quote.items(source)
  }
  for entry in fills.split("\u{1E}") {
    let parts = entry
      .to_owned()
      .split("\u{1F}")
      .to_array()
      .map(s => s.to_owned())
    guard parts.length() >= 3 else { continue }
    let hole = parts[0]
    let kind = parts[1]
    let codes = []
    for value in parts[2:] {
      codes.push(code_of(kind, value))
    }
    if hole.has_suffix("*") {
      tpl = tpl.splice(hole[:hole.length() - 1].to_owned(), codes)
    } else {
      guard codes.length() > 0 else { continue }
      tpl = tpl.set(hole, codes[0])
    }
  }
  tpl.render().to_string() catch {
    e => e.to_string()
  }
}

///|
/// The code one value makes, by the kind the page asked for.
fn code_of(kind : String, value : String) -> @quote.Code raise @quote.Refused {
  match kind {
    "ident" => @quote.ident(value)
    "string" => @quote.string(value)
    "expr" => @quote.expr(value).render()
    "ty" => @quote.ty(value).render()
    _ => @quote.string(value)
  }
}

///|
struct Describe {}

///|
impl @gen.Generator for Describe with fn name(_) {
  "describe"
}

///|
impl @gen.Generator for Describe with fn generate(_, decls) {
  let out = []
  for decl in decls {
    guard decl is Struct(name~, fields~, attrs~, ..) &&
      @attr.find(attrs, "demo.describe") is Some(_) else {
      continue
    }
    let text = name + "(" + fields.map(f => f.name).join(", ") + ")"
    let source =
      #|fn $T::describe(self : $T) -> String {
      #|  ignore(self)
      #|  $text
      #|}
    out.push(
      @quote.items(source)
      .set("T", @quote.ident(name))
      .set("text", @quote.string(text))
      .render(),
    )
  }
  @quote.join(out)
}

///|
struct Getters {}

///|
impl @gen.Generator for Getters with fn name(_) {
  "getters"
}

///|
impl @gen.Generator for Getters with fn generate(_, decls) {
  let out = []
  for decl in decls {
    guard decl is Struct(name~, fields~, attrs~, ..) else { continue }
    guard @attr.find(attrs, "demo.getters") is Some(annotation) else {
      continue
    }
    let skip = @attr.Spec::new("demo.getters")
      .many("skip", Ident)
      .bind(annotation)
      .strs("skip")
    for f in fields {
      guard !skip.contains(f.name) else { continue }
      let source =
        #|fn $T::$field(self : $T) -> $Ty {
        #|  self.$field
        #|}
      out.push(
        @quote.items(source)
        .set("T", @quote.ident(name))
        .set("field", @quote.ident(f.name))
        .set("Ty", @quote.ty(f.ty).render())
        .render(),
      )
    }
  }
  @quote.join(out)
}

///|
struct Route {}

///|
impl @gen.Generator for Route with fn name(_) {
  "route"
}

///|
impl @gen.Generator for Route with fn generate(_, decls) {
  let out = []
  for decl in decls {
    guard decl is Func(name~, attrs~, ..) else { continue }
    guard @attr.find(attrs, "app.route") is Some(annotation) else { continue }
    let args = @attr.Spec::new("app.route")
      .positional("path", Str)
      .many("tag", Str)
      .bind(annotation)
    let path = args.str("path").unwrap_or("/")
    let tags = args.strs("tag")
    let source =
      #|fn $reg(router : Router) -> Unit {
      #|  router.add($path, $handler, [$tags*])
      #|}
    out.push(
      @quote.items(source)
      .set("reg", @quote.ident("register_" + name))
      .set("path", @quote.string(path))
      .set("handler", @quote.ident(name))
      .splice("tags", tags.map(t => @quote.string(t)))
      .render(),
    )
  }
  @quote.join(out)
}

///|
/// One of the generators above over one input, as the file it would write.
pub fn generate(which : String, source : String) -> String {
  file_of(which, source) catch {
    e => e.to_string()
  }
}

///|
fn file_of(which : String, source : String) -> String raise {
  match which {
    "getters" => @gen.render(Getters::{ }, [("models.mbt", source)])
    "route" => @gen.render(Route::{ }, [("routes.mbt", source)])
    _ => @gen.render(Describe::{ }, [("models.mbt", source)])
  }
}

///|
extern "js" fn register(
  template : (String, String, String) -> String,
  generate : (String, String) -> String,
) -> Unit =
  #| (t, g) => { globalThis.moonast = { template: t, generate: g }; }

///|
fn main {
  register(template, generate)
}
