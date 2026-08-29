//// The paper's asserted inputs, weak composition, and typed endpoints.

import bank_auth.{PaymentDetails, Pin, Statement, Tan, TransactionId}
import bank_auth/bank
import bank_auth/customer
import bank_auth/protocol
import generate
import gleam/erlang/process
import gleam/list
import gleeunit
import pacta/protocol/emit
import pacta/protocol/graph
import pacta/protocol/relations
import pacta/protocol/weave

pub fn main() -> Nil {
  gleeunit.main()
}

fn composition_count(branching: weave.Branching) -> #(Int, Bool) {
  let weave.Composition(candidates:, truncated:) =
    weave.compose(
      protocol.authentication().spec,
      protocol.banking().spec,
      weave.Options(..weave.defaults(), branching:),
    )

  #(list.length(candidates), truncated)
}

pub fn table_1_row_7_pintan_and_bank_counts_test() -> Nil {
  // Table 1 reports one result only when weak branching is enabled.
  assert composition_count(weave.Strong) == #(0, False)
  assert composition_count(weave.Weak) == #(1, False)
  assert composition_count(weave.Correlating) == #(0, False)
  assert composition_count(weave.All) == #(1, False)

  let assert weave.Composition(candidates: [candidate], truncated: False) =
    protocol.composition()
  assert candidate.relaxations != []
}

pub fn the_inputs_have_the_cross_requirements_described_by_the_paper_test() -> Nil {
  assert graph.compile(protocol.banking())
    == Error(graph.UnmetRequirement("pin"))
  assert graph.compile(protocol.authentication())
    == Error(graph.UnmetRequirement("pay"))
}

pub fn the_selected_composition_projects_to_dual_endpoints_test() -> Nil {
  let assert Ok(composed) = protocol.composed()
  let assert Ok([customer, bank]) = graph.compile(composed)

  assert customer.role == "Customer"
  assert bank.role == "Bank"
  let assert Ok(_) = relations.dual(customer, bank)
  Nil
}

pub fn a_pin_authorises_a_statement_test() -> Nil {
  let inbox = process.new_subject()
  let assert Ok(started) =
    bank.start(serving: inbox, pin: Pin("1234"), tan: Tan("5678"), balance: 100)

  assert customer.statement(Pin("1234"), at: started, from: inbox)
    == Ok(Statement(balance: 100))
}

pub fn a_successful_tan_authorises_payment_details_test() -> Nil {
  let inbox = process.new_subject()
  let assert Ok(started) =
    bank.start(serving: inbox, pin: Pin("1234"), tan: Tan("5678"), balance: 100)

  assert customer.pay(
      Pin("1234"),
      Tan("5678"),
      PaymentDetails(to: "merchant", amount: 25),
      at: started,
      from: inbox,
    )
    == Ok(customer.Paid(TransactionId(1)))
}

pub fn a_failed_tan_returns_to_banking_without_payment_details_test() -> Nil {
  let inbox = process.new_subject()
  let assert Ok(started) =
    bank.start(serving: inbox, pin: Pin("1234"), tan: Tan("5678"), balance: 100)

  assert customer.pay(
      Pin("1234"),
      Tan("wrong"),
      PaymentDetails(to: "merchant", amount: 25),
      at: started,
      from: inbox,
    )
    == Ok(customer.RejectedTan(TransactionId(1)))
}

pub fn a_failed_pin_never_reaches_the_banking_loop_test() -> Nil {
  let inbox = process.new_subject()
  let assert Ok(started) =
    bank.start(serving: inbox, pin: Pin("1234"), tan: Tan("5678"), balance: 100)

  assert customer.statement(Pin("wrong"), at: started, from: inbox)
    == Error(customer.PinRejected)
}

pub fn the_selected_candidate_keeps_its_relaxation_evidence_test() -> Nil {
  let assert Ok(selection) = protocol.selection()

  assert protocol.explanations(selection)
    == [
      "arm `statement` could not compose and was left as it was",
      "arm `fail` could not compose and was left as it was",
      "arm `logout` could not compose and was left as it was",
      "arm `fail` could not compose and was left as it was",
    ]
}

pub fn the_generated_modules_are_current_test() -> Nil {
  let assert Ok(selection) = protocol.selection()
  let assert Ok(wanted) = generate.modules(selection)

  assert list.map(emit.review(wanted, against: generate.on_disk), emit.describe)
    == [
      "bank_auth/protocol/pin_tan_banking/customer: up to date",
      "bank_auth/protocol/pin_tan_banking/bank: up to date",
      "bank_auth/protocol/pin_tan_banking/selection: up to date",
    ]
}
