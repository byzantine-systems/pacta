# Examples

Runnable example projects for the `pacta` library. Each example is a self-contained Gleam project with unit / integration tests.

```sh
cd examples/<example>
gleam test
gleam run -m generate
gleam run -m generate check
```

## Session Types (`pacta/session`, `pacta/protocol`)

| Example | Description |
|---|---|
| [`atm`](https://github.com/byzantine-systems/pacta/tree/main/examples/atm) | A protocol specification, projected onto both participants, generated into typed positions, and driven from a `gen_statem` |
| [`bank_auth`](https://github.com/byzantine-systems/pacta/tree/main/examples/bank_auth) | Bocchi-Orchard-Voinea's asserted PIN/TAN banking protocols, weakly composed and generated into typed participants |

### Composed PIN/TAN banking

This example is sourced from [*A Theory of Composing Protocols*](https://doi.org/10.22152/programming-journal.org/2023/7/6), *The Art, Science, and Engineering of Programming* 7(2), article 6, 2023.

#### Transcription into Pacta

The contact points and control flow are the paper's:

- Banking requires `pin` before entering its `statement` / `payment` / `logout`
  loop. 
    - Payment asserts `pay` and consumes `tan`.
    - Logout consumes `pin`. 
- Authentication receives a PIN and asserts `pin` on success. Its loop consumes `pay`, sends a transaction id, receives a TAN, and asserts `tan` on success.
- Strong composition is empty. Weak composition puts the authentication loop inside the banking payment arm and leaves failed authentication arms alone.

The adaptation is explicit. The paper writes server-local `?` and `!` actions. Pacta specifications are global, so these become directed `Customer -> Bank` and `Bank -> Customer` messages. Branch labels carry `Nil`, and the paper's abstract payload names receive executable representations in `bank_auth`.

### ATM

The ATM protocol from Laumann, Munksgaard and Larsen, [*Session Types for Rust*](https://munksgaard.me/papers/laumann-munksgaard-larsen.pdf).

- One global specification, projected onto a `Client` and an `Atm`.
- Recursion, so it is a protocol that **cannot** be written as a nested Gleam type at all: the generator flattens it into named positions with an edge back to the head of the loop.
- The machine side as a `protocol_machine`, the client side walked by hand, both checked against the same specification.
- Duality and subtyping decided over the projected graphs, including the answer to the "can I add a branch without breaking everyone" question the paper raises and leaves to the reader.
- Generated modules committed, with `gleam run -m generate check` to fail CI when they go stale.

The example depends on `pacta` by path and on [`eparch`](https://hex.pm/packages/eparch) from Hex, because the machine and client sides drive their positions from a `gen_statem` and so import `eparch/state_machine` directly.

