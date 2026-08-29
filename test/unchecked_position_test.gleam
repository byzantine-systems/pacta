////
//// Audits the one unchecked boundary used by generated protocol modules.
////
//// `core.unchecked_position` has to be public because Gleam has no
//// package-private visibility. These tests compensate by checking both sides
//// of the generation boundary: what the emitter produces, and every Gleam
//// source file shipped by this repository and its examples.
////

import atm_protocol
import gleam/list
import gleam/result
import gleam/string
import pacta/protocol/emit
import simplifile

const unchecked_name = "unchecked_position"

const unchecked_call = "core.unchecked_position(channel)"

fn code_lines_containing(source: String, needle: String) -> List(String) {
  source
  |> string.split("\n")
  |> list.filter(fn(line) {
    let trimmed = string.trim_start(line)
    !string.starts_with(trimmed, "//") && string.contains(line, needle)
  })
}

fn core_owns_exactly_one_primitive_and_one_internal_call(
  source: String,
) -> Bool {
  code_lines_containing(source, unchecked_name)
  |> list.map(string.trim)
  == [
    "pub fn unchecked_position(channel: Channel(from, msg)) -> Channel(to, msg) {",
    "unchecked_position(channel)",
  ]
}

fn emitter_owns_exactly_one_template_use(source: String) -> Bool {
  code_lines_containing(source, unchecked_name)
  |> list.map(string.trim)
  == ["<> \"\\n  core.unchecked_position(channel)\\n}\""]
}

fn calls_are_single_expression_bodies(lines: List(String)) -> Bool {
  case lines {
    [previous, current, next, ..rest] -> {
      let current_is_safe = case string.contains(current, unchecked_name) {
        False -> True
        True ->
          string.trim(current) == unchecked_call
          && string.ends_with(string.trim(previous), "{")
          && string.trim(next) == "}"
      }

      current_is_safe
      && calls_are_single_expression_bodies([current, next, ..rest])
    }
    remaining ->
      list.all(remaining, fn(line) { !string.contains(line, unchecked_name) })
  }
}

fn unfolding_section(source: String) -> Result(String, Nil) {
  case string.split(source, "\n// UNFOLDING\n") {
    [_, unfolding_and_choices] ->
      case string.split(unfolding_and_choices, "\n// CHOICES\n") {
        [unfolding, ..] -> Ok(unfolding)
        [] -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn generated_source_is_safe(source: String) -> Bool {
  let uses = code_lines_containing(source, unchecked_name)
  let positions =
    source
    |> string.split("\n")
    |> list.filter(string.starts_with(_, "pub type "))

  case unfolding_section(source) {
    Error(Nil) -> False
    Ok(unfolding) -> {
      let unfolding_uses = code_lines_containing(unfolding, unchecked_name)

      string.contains(source, "written by")
      && string.contains(source, "`pacta/protocol/emit`")
      && list.length(uses) == list.length(positions)
      && uses == unfolding_uses
      && list.all(uses, fn(line) { string.trim(line) == unchecked_call })
      && calls_are_single_expression_bodies(string.split(unfolding, "\n"))
    }
  }
}

fn existing_source_trees(
  project: String,
) -> Result(List(String), simplifile.FileError) {
  use trees <- result.try(
    list.try_map(["src", "test", "dev"], fn(name) {
      let directory = project <> "/" <> name
      use is_directory <- result.try(simplifile.is_directory(directory))

      case is_directory {
        True -> simplifile.get_files(in: directory)
        False -> Ok([])
      }
    }),
  )

  Ok(list.flatten(trees))
}

fn example_source_files() -> Result(List(String), simplifile.FileError) {
  use entries <- result.try(simplifile.read_directory(at: "examples"))
  use sources <- result.try(
    list.try_map(entries, fn(entry) {
      let project = "examples/" <> entry
      use is_project <- result.try(simplifile.is_directory(project))

      case is_project {
        True -> existing_source_trees(project)
        False -> Ok([])
      }
    }),
  )

  Ok(list.flatten(sources))
}

fn repository_source_files() -> Result(List(String), simplifile.FileError) {
  use library <- result.try(simplifile.get_files(in: "src"))
  use tests <- result.try(simplifile.get_files(in: "test"))
  use examples <- result.try(example_source_files())

  Ok(
    [library, tests, examples]
    |> list.flatten
    |> list.filter(string.ends_with(_, ".gleam")),
  )
}

fn source_is_safe(path: String, source: String) -> Bool {
  let uses = code_lines_containing(source, unchecked_name)

  case uses, path {
    [], _ -> True
    // The audit necessarily names the function whose appearances it checks.
    _, "test/unchecked_position_test.gleam" -> True
    _, "src/pacta/session/core.gleam" ->
      core_owns_exactly_one_primitive_and_one_internal_call(source)
    _, "src/pacta/protocol/emit.gleam" ->
      emitter_owns_exactly_one_template_use(source)
    _, _ -> generated_source_is_safe(source)
  }
}

pub fn emitter_confines_unchecked_position_to_unfolding_functions_test() -> Nil {
  let assert Ok(modules) = emit.modules(atm_protocol.atm(), under: "generated")

  list.each(modules, fn(module) {
    assert generated_source_is_safe(module.source)
  })
}

pub fn repository_has_no_handwritten_unchecked_position_calls_test() -> Nil {
  let assert Ok(paths) = repository_source_files()

  list.each(paths, fn(path) {
    let assert Ok(source) = simplifile.read(path)

    // Pairing the path with the result makes a failure identify its source.
    assert #(path, source_is_safe(path, source)) == #(path, True)
  })
}
