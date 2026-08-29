//// Bocchi, Orchard, and Voinea's asserted banking and PIN/TAN protocols.
////
//// `banking` is S'B and `authentication` is S'A from Example 1 of *A Theory
//// of Composing Protocols* (article page 6:7). Their unique weak composition,
//// SBA, is derived in Example 2 (article page 6:13).
////
//// The paper writes both inputs from the bank's local point of view. This
//// module makes the same actions global: `?` becomes `Customer -> Bank`, `!`
//// becomes `Bank -> Customer`, and each local branch becomes a directed
//// `Choice` between those roles. Contact-point placement and recursion follow
//// the paper.

import gleam/list
import gleam/result
import pacta/protocol/spec
import pacta/protocol/weave

/// Why the asserted inputs did not determine one complete composition.
///
/// ## Example
///
/// ```gleam
/// case protocol.composed() {
///   Ok(protocol) -> use(protocol)
///   Error(protocol.SearchTruncated) -> try_with_a_larger_limit()
///   Error(protocol.UnexpectedCandidateCount(_)) -> refine_the_contact_points()
/// }
/// ```
///
pub type CompositionError {
  /// The candidate limit was reached, so the returned set is incomplete.
  SearchTruncated
  /// Contact points admitted either no composition or more than one.
  UnexpectedCandidateCount(found: Int)
}

/// The author's accepted protocol together with its derivation evidence.
///
/// The constructor is private so the protocol and candidate cannot drift
/// apart. Generators can obtain the protocol and the required relaxations
/// through the accessors below.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(selection) = protocol.selection()
/// let composed = protocol.selected_protocol(selection)
/// ```
///
pub opaque type Selection {
  Selection(protocol: spec.Protocol, candidate: weave.Candidate)
}

/// S'A: PIN authentication followed by one TAN check per payment.
///
/// A successful PIN asserts the reusable `pin` guarantee. Inside the loop,
/// authentication consumes `pay` before issuing a transaction id and checking
/// a TAN. A successful TAN asserts the one-use `tan` guarantee needed by the
/// matching banking payment.
///
/// ## Example
///
/// ```gleam
/// let authentication = protocol.authentication()
/// ```
///
pub fn authentication() -> spec.Protocol {
  spec.Protocol(
    name: "pin_tan",
    roles: ["Customer", "Bank"],
    initial: "AuthenticatingPin",
    imports: imports(),
    spec: spec.Message(
      from: "Customer",
      to: "Bank",
      label: "pin",
      payload: "bank_auth.Pin",
      then: spec.Choice(at: "Bank", to: "Customer", branches: [
        spec.Branch(
          "ok",
          "Nil",
          spec.Assert(
            "pin",
            spec.Loop(
              "authentication",
              spec.Consume(
                "pay",
                spec.Message(
                  from: "Bank",
                  to: "Customer",
                  label: "id",
                  payload: "bank_auth.TransactionId",
                  then: spec.Message(
                    from: "Customer",
                    to: "Bank",
                    label: "tan",
                    payload: "bank_auth.Tan",
                    then: spec.Choice(at: "Bank", to: "Customer", branches: [
                      spec.Branch(
                        "ok",
                        "Nil",
                        spec.Assert("tan", spec.Continue("authentication")),
                      ),
                      spec.Branch(
                        "fail",
                        "Nil",
                        spec.Continue("authentication"),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        spec.Branch("fail", "Nil", spec.End),
      ]),
    ),
  )
}

/// S'B: banking guarded by successful PIN and TAN authentication.
///
/// The menu is available only while `pin` is live. Statements reuse that
/// guarantee. A payment asserts `pay`, consumes one successful `tan`, accepts
/// payment details, and loops. Logout consumes `pin` and ends.
///
/// ## Example
///
/// ```gleam
/// let banking = protocol.banking()
/// ```
///
pub fn banking() -> spec.Protocol {
  spec.Protocol(
    name: "banking",
    roles: ["Customer", "Bank"],
    initial: "Banking",
    imports: imports(),
    spec: spec.Require(
      "pin",
      spec.Loop(
        "banking",
        spec.Choice(at: "Customer", to: "Bank", branches: [
          spec.Branch(
            "statement",
            "Nil",
            spec.Message(
              from: "Bank",
              to: "Customer",
              label: "statement",
              payload: "bank_auth.Statement",
              then: spec.Continue("banking"),
            ),
          ),
          spec.Branch(
            "payment",
            "Nil",
            spec.Assert(
              "pay",
              spec.Consume(
                "tan",
                spec.Message(
                  from: "Customer",
                  to: "Bank",
                  label: "details",
                  payload: "bank_auth.PaymentDetails",
                  then: spec.Continue("banking"),
                ),
              ),
            ),
          ),
          spec.Branch("logout", "Nil", spec.Consume("pin", spec.End)),
        ]),
      ),
    ),
  )
}

/// Run the paper's weak composition without hiding its evidence.
///
/// Strong composition returns no candidates; weak composition derives the one
/// SBA protocol shown in the paper's Example 2.
///
/// ## Example
///
/// ```gleam
/// let weave.Composition(candidates:, truncated:) = protocol.composition()
/// ```
///
pub fn composition() -> weave.Composition {
  weave.compose(
    authentication().spec,
    banking().spec,
    weave.Options(..weave.defaults(), branching: weave.Weak),
  )
}

/// Select the unique complete weak composition with its derivation evidence.
///
/// No candidate is selected from a truncated or ambiguous search. The author
/// must refine contact points or the search configuration instead.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(selection) = protocol.selection()
/// let evidence = protocol.explanations(selection)
/// ```
///
pub fn selection() -> Result(Selection, CompositionError) {
  case weave.select_unique(composition()) {
    Error(weave.SearchTruncated) -> Error(SearchTruncated)
    Error(weave.UnexpectedCandidateCount(found)) ->
      Error(UnexpectedCandidateCount(found))
    Ok(candidate) ->
      Ok(Selection(
        protocol: spec.Protocol(
          name: "pin_tan_banking",
          roles: ["Customer", "Bank"],
          initial: "AuthenticatingPin",
          imports: imports(),
          spec: candidate.protocol,
        ),
        candidate:,
      ))
  }
}

/// Return the global protocol accepted by the author.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(selection) = protocol.selection()
/// let composed = protocol.selected_protocol(selection)
/// ```
///
pub fn selected_protocol(selection: Selection) -> spec.Protocol {
  selection.protocol
}

/// Explain every branching relaxation required by the selected derivation.
///
/// An empty list means strong branching was sufficient.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(selection) = protocol.selection()
/// let explanations = protocol.explanations(selection)
/// ```
///
pub fn explanations(selection: Selection) -> List(String) {
  list.map(selection.candidate.relaxations, weave.describe)
}

/// Return only the selected global protocol.
///
/// Use `selection` in generators so its relaxation evidence is not discarded.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(composed) = protocol.composed()
/// let assert Ok([customer, bank]) = graph.compile(composed)
/// ```
///
pub fn composed() -> Result(spec.Protocol, CompositionError) {
  selection()
  |> result.map(selected_protocol)
}

fn imports() -> List(String) {
  ["import bank_auth"]
}
