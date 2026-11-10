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
/// Why the registrar stopped, as one sentence. An annotation that does not bind
/// is reported by `moonast/attr` and arrives here already naming the file, line
/// and column it stands at; the rules this registrar enforces add their own place
/// the same way.
#derive(Debug)
pub(all) suberror Refused {
  Bad(msg~ : String)
}

///|
pub extend Refused with Debug::{to_repr}

///|
pub impl Show for Refused with fn output(self, logger) {
  let text = match self {
    Bad(msg~) => msg
  }
  logger.write_string(text)
}

///|
pub extend Refused with Show::{to_string, output}

///|
/// Where a declaration stands: the file `moonast/gen` read it from, and the
/// position, `file:line:column`, a message about it points at.
struct Place {
  file : String
  at : String
}

///|
fn place_of(decl : @gen.Decl) -> Place {
  let start = decl.raw().loc().start
  let file = decl.file()
  { file, at: "\{file}:\{start.lnum}:\{start.column()}", }
}

///|
/// A refusal that names the place it is about.
fn refuse(place : Place, msg : String) -> Refused {
  Bad(msg="\{place.at}: \{msg}")
}

///|
/// `#proton.command(contract=list_users_command)`: the value the command is bound
/// to. It is a name, or a name after a qualifier, because the annotation grammar
/// has no `@pkg.name`.
fn command_spec() -> @attr.Spec {
  @attr.Spec::new("proton.command").required("contract", Path)
}

///|
/// Bind an annotation, handing `moonast/attr` the file so its message names the
/// file, line and column the annotation stands at. Nothing is added here: the
/// payload's place is its own, not the declaration's.
fn arguments(
  annotation : @attribute.Attribute,
  place : Place,
) -> @attr.Args raise {
  command_spec().bind(annotation, file=place.file) catch {
    e => raise Bad(msg=e.to_string())
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
    let place = place_of(decl)
    guard @attr.malformed(attrs, "proton").is_empty() else {
      raise refuse(place, "cannot make sense of a `#proton.` annotation")
    }
    let marked = @attr.all(attrs, "proton.command")
    guard !marked.is_empty() else { continue }
    guard marked.length() == 1 else {
      raise refuse(place, "only one `#proton.command` attribute is allowed")
    }
    for annotation in @attr.under(attrs, "proton") {
      let call = @attr.name_of(annotation).unwrap_or("")
      guard call == "proton.command" else {
        raise refuse(place, "unknown annotation `#\{call}` on `\{name}`")
      }
    }
    let contract = arguments(marked[0], place).str("contract").unwrap_or("")
    // A command is a function whose parameters are all named and typed, the
    // receiver first when it is a method.
    let typed = params.map(param => {
      guard param.name is Some(name) && param.ty is Some(ty) else {
        raise refuse(place, "`\{name}` takes only named, typed parameters")
      }
      guard param.pass is Positional else {
        raise refuse(place, "`\{name}` takes only positional parameters")
      }
      (name, ty)
    })
    let rest = match owner {
      None => typed
      Some(receiver) => {
        guard typed.length() > 0 else {
          raise refuse(
            place,
            "`\{name}` is a method of \{receiver} and needs `self`",
          )
        }
        let (first, first_ty) = typed[0]
        guard first == "self" && first_ty == receiver else {
          raise refuse(
            place,
            "a method command starts with `self : \{receiver}`",
          )
        }
        typed[1:].to_owned()
      }
    }
    let context = match rest {
      [(first, ty), ..] if first == "context" => {
        guard takes_context(ty) else {
          raise refuse(place, "`context` takes @proton.CommandContext")
        }
        true
      }
      _ => false
    }
    let request = if context { rest.length() - 1 } else { rest.length() }
    guard request <= 1 else {
      raise refuse(
        place,
        "`\{name}` takes one request value and an optional leading CommandContext",
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
          msg="<inputs>: `\{out[earlier].name}` and `\{command.name}` are both bound to \{command.contract}",
        )
      }
    }
  }
  out
}
