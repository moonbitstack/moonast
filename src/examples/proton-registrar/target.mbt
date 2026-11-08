///|
/// One command: the function that handles it, the type it is a method of, and the
/// contract it is bound to.
struct Command {
  name : String
  receiver : String?
  contract : String
  context : Bool
  request : Bool
}

///|
/// Why the registrar stopped. An annotation that does not bind is reported by
/// `moonast/attr`; this is for the rules the annotation's values have to obey.
#derive(Debug)
pub(all) suberror Refused {
  Bad(at~ : String, msg~ : String)
}

///|
pub extend Refused with Debug::{to_repr}

///|
pub impl Show for Refused with fn output(self, logger) {
  let text = match self {
    Bad(at~, msg~) => "\{at}: \{msg}"
  }
  logger.write_string(text)
}

///|
pub extend Refused with Show::{to_string, output}

///|
/// Where a declaration stands, so a message can say which one it is about.
fn at(decl : @gen.Decl) -> String {
  let start = decl.raw().loc().start
  "\{file_of(decl)}:\{start.lnum}:\{start.column()}"
}

///|
fn file_of(decl : @gen.Decl) -> String {
  match decl {
    Struct(file~, ..) | Enum(file~, ..) | Func(file~, ..) | Other(file~, ..) =>
      file
  }
}

///|
/// `#proton.command(contract=list_users_command)`: the value the command is bound
/// to. It is a name, or a name after a qualifier, because the annotation grammar
/// has no `@pkg.name`.
fn command_spec() -> @attr.Spec {
  @attr.Spec::new("proton.command").required("contract", Path)
}

///|
/// Bind an annotation, putting the file in front of what `moonast/attr` says about
/// it: its message names the line and column, and the reader needs the file those
/// are in.
fn arguments(
  annotation : @attribute.Attribute,
  at~ : String,
) -> @attr.Args raise {
  command_spec().bind(annotation) catch {
    e => raise Bad(at~, msg=e.to_string())
  }
}

///|
/// Whether a parameter is the one a handler takes a `CommandContext` in. Both the
/// short and the long package name are in use.
fn takes_context(ty : String) -> Bool {
  ty == "@proton.CommandContext" || ty == "@proton_command.CommandContext"
}

///|
/// The commands in one parse, in source order. A function without
/// `#proton.command` is not one of them.
fn commands_of(decls : Array[@gen.Decl]) -> Array[Command] raise {
  let out = []
  for decl in decls {
    guard decl is Func(name~, owner~, params~, attrs~, ..) else { continue }
    let at = at(decl)
    guard @attr.malformed(attrs, "proton").is_empty() else {
      raise Bad(at~, msg="cannot make sense of a `#proton.` annotation")
    }
    let marked = @attr.all(attrs, "proton.command")
    guard !marked.is_empty() else { continue }
    guard marked.length() == 1 else {
      raise Bad(at~, msg="only one `#proton.command` attribute is allowed")
    }
    for annotation in @attr.under(attrs, "proton") {
      let call = @attr.name_of(annotation).unwrap_or("")
      guard call == "proton.command" else {
        raise Bad(at~, msg="unknown annotation `#\{call}` on `\{name}`")
      }
    }
    let contract = arguments(marked[0], at~).str("contract").unwrap_or("")
    // A command is a function whose parameters are all named and typed, the
    // receiver first when it is a method.
    let typed = params.map(param => {
      guard param.name is Some(name) && param.ty is Some(ty) else {
        raise Bad(at~, msg="`\{name}` takes only named, typed parameters")
      }
      guard param.pass is Positional else {
        raise Bad(at~, msg="`\{name}` takes only positional parameters")
      }
      (name, ty)
    })
    let rest = match owner {
      None => typed
      Some(receiver) => {
        guard typed.length() > 0 else {
          raise Bad(
            at~,
            msg="`\{name}` is a method of \{receiver} and needs `self`",
          )
        }
        let (first, first_ty) = typed[0]
        guard first == "self" && first_ty == receiver else {
          raise Bad(
            at~,
            msg="a method command starts with `self : \{receiver}`",
          )
        }
        typed[1:].to_owned()
      }
    }
    let context = match rest {
      [(first, ty), ..] if first == "context" => {
        guard takes_context(ty) else {
          raise Bad(at~, msg="`context` takes @proton.CommandContext")
        }
        true
      }
      _ => false
    }
    let request = if context { rest.length() - 1 } else { rest.length() }
    guard request <= 1 else {
      raise Bad(
        at~,
        msg="`\{name}` takes one request value and an optional leading CommandContext",
      )
    }
    out.push({
      name,
      receiver: owner,
      contract,
      context,
      request: request == 1,
    })
  }
  // Two commands bound to one contract would register twice.
  for index, command in out {
    for earlier in 0..<index {
      guard out[earlier].contract != command.contract else {
        raise Bad(
          at="<inputs>",
          msg="`\{out[earlier].name}` and `\{command.name}` are both bound to \{command.contract}",
        )
      }
    }
  }
  out
}
