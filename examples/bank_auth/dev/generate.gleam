//// Generate or review the typed modules for the selected composition.
////
//// ```sh
//// gleam run -m generate
//// gleam run -m generate check
//// ```

import argv
import bank_auth/protocol
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import pacta/protocol/emit
import pacta/protocol/graph
import simplifile

pub const root = "src"

pub const prefix = "bank_auth/protocol"

pub fn main() -> Nil {
  let selection = case protocol.selection() {
    Ok(selection) -> selection
    Error(protocol.SearchTruncated) ->
      panic as "composition search was truncated; generated modules were not written"
    Error(protocol.UnexpectedCandidateCount(found)) -> {
      let message =
        "expected exactly one composition candidate; found "
        <> int.to_string(found)
      panic as message
    }
  }
  let assert Ok(modules) = modules(selection)

  case argv.load().arguments {
    ["check"] -> check(modules)
    _ -> write(modules)
  }
}

/// Build the participant modules and their reviewed selection evidence.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(selection) = protocol.selection()
/// let assert Ok(modules) = generate.modules(selection)
/// ```
///
pub fn modules(
  selection: protocol.Selection,
) -> Result(List(emit.Module), graph.Error) {
  use participants <- result.try(emit.modules(
    protocol.selected_protocol(selection),
    under: prefix,
  ))
  Ok(list.append(participants, [evidence_module(selection)]))
}

fn evidence_module(selection: protocol.Selection) -> emit.Module {
  let selected = protocol.selected_protocol(selection)
  let explanations = case protocol.explanations(selection) {
    [] -> ["derivable with strong branching"]
    explanations -> explanations
  }
  let bullets =
    explanations
    |> list.map(fn(explanation) { "//// - " <> explanation })
    |> string.join("\n")

  emit.Module(
    name: prefix <> "/" <> selected.name <> "/selection",
    source: "//// The reviewed composition selection for `"
      <> selected.name
      <> "`.\n////\n"
      <> "//// Written by the bank-auth generator; manual edits are lost.\n"
      <> "////\n"
      <> "//// Source: Bocchi, Orchard and Voinea, Examples 1 and 2.\n"
      <> "//// Branching mode: `Weak`.\n"
      <> "//// Acceptance: one candidate from a complete search.\n"
      <> "////\n"
      <> "//// Required branching relaxations:\n"
      <> "////\n"
      <> bullets
      <> "\n////\n"
      <> "/// The branching mode used for this reviewed selection.\n"
      <> "pub const branching = \"Weak\"\n",
  )
}

fn write(modules: List(emit.Module)) -> Nil {
  use module <- list.each(modules)
  let path = emit.path(module, in: root)

  let assert Ok(_) = simplifile.create_directory_all(directory(path))
  let assert Ok(_) = simplifile.write(to: path, contents: module.source)

  io.println("wrote " <> path)
}

fn check(modules: List(emit.Module)) -> Nil {
  let reviews = emit.review(modules, against: on_disk)

  list.each(reviews, fn(review) { io.println(emit.describe(review)) })

  case emit.agreed(reviews) {
    True -> Nil
    False -> panic as "generated protocol modules are out of date"
  }
}

pub fn on_disk(module: emit.Module) -> Result(String, Nil) {
  simplifile.read(emit.path(module, in: root))
  |> result.replace_error(Nil)
}

fn directory(path: String) -> String {
  path
  |> string.split("/")
  |> list.reverse
  |> list.drop(1)
  |> list.reverse
  |> string.join("/")
}
