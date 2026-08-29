# Pacta

[![Package Version](https://img.shields.io/hexpm/v/pacta)](https://hex.pm/packages/pacta)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/pacta/)
[![Erlang Compatible](https://img.shields.io/badge/target-erlang-b83998)](https://www.erlang.org/)
![License](https://img.shields.io/github/license/byzantine-systems/pacta)

[![Built with Nix](https://builtwithnix.org/badge.svg)](https://builtwithnix.org)
[![[Nix] Build & Test](https://github.com/byzantine-systems/pacta/actions/workflows/build.yml/badge.svg)](https://github.com/byzantine-systems/pacta/actions/workflows/build.yml)

> **Pacta sunt servanda pietate**, agreements must be kept.

Pacta is an experiment with [session types](https://en.wikipedia.org/wiki/Session_type) for Gleam: a two-party protocol becomes a *type*, and using a conversation wrongly becomes a compile error rather than a bug you find in production. It is built on top of [`eparch`](https://hex.pm/packages/eparch) and `gen_statem`.

> **Status: experimental.** The API moves. This package exists so that it *can* move without dragging `eparch`'s OTP wrappers through a major version every time it does.

## The two layers

A protocol as a type, walked step by step:

| Module | Purpose |
|---|---|
| `pacta/session/core` | The protocol grammar (`Send` / `Recv` / `Choose` / `Offer` / `Done`) as continuation-carrying phantom markers, the opaque `Channel(protocol, msg)`, and the steps that walk it. Does no I/O. |
| `pacta/session/duality` | `Dual(a, b)` witnesses proving two protocols fit together, their combinators, `flip`, `connect`, `opposite`. |
| `pacta/session/patterns` | Reusable protocol fragments (`Request`/`Serve`, `Propose`/`Decide`, `Coordinate`/`Participate`) and their witnesses. |
| `pacta/protocol_machine` | Drives a protocol from a `gen_statem`, by lowering onto `eparch/state_machine`. |

And a specification layer *beside* it, which runs before compilation rather than during it. This is what buys recursion and more than two participants, neither of which the type-level encoding can express:

| Module | Purpose |
|---|---|
| `pacta/protocol/spec` | The specification language: `Protocol`, `Spec`, directed `Choice`, `Loop`/`Continue`, and the `Assert`/`Require`/`Consume` contact points. |
| `pacta/protocol/graph` | Well-formedness checking and projection onto each participant, producing a flat cyclic state graph per role. |
| `pacta/protocol/relations` | Decides duality, equivalence and subtyping over projected graphs by coinduction. |
| `pacta/protocol/weave` | Interleaving composition: weaves two protocols into one, guided by their contact points. |
| `pacta/protocol/emit` | Writes a projected graph out as Gleam source, one module per participant, plus `review` for checking committed output against the specification. |

Full API reference: <https://hexdocs.pm/pacta>.

## Relationship to Eparch

[`eparch`](https://github.com/byzantine-systems/eparch) wraps Erlang/OTP behaviours (`gen_statem`, `gen_event`) in a type-safe API. Pacta is the experimental layer that used to live inside it, split out so the two can version independently.

The dependency is one-way and narrow: only `pacta/protocol_machine` imports `eparch`, and only to lower a protocol position onto `eparch/state_machine`. Everything else here is pure.

## Installation

```sh
gleam add pacta
```

### Usage

See the [Session Types guide](https://hexdocs.pm/pacta/docs/session_types.html) for the full walkthrough, or run the [`examples/atm`](https://hexdocs.pm/pacta/examples/readme.html) project, which specifies a protocol once, projects it onto both participants, generates typed positions from it, and drives one side from a `gen_statem`.

## Development

The project uses [devenv](https://devenv.sh/) and [Nix](https://nixos.org/) for a hermetic development environment:

```sh
nix develop
```

Or, if you are already using [direnv](https://direnv.net/):

```sh
direnv allow .
```
