//// The customer side of the paper's composed PIN/TAN banking protocol.
////
//// The generated positions expose the key dependency directly: a payment
//// reaches `AtDetails` only through the successful TAN branch. A failed TAN
//// returns to `Banking`, so the customer can safely choose another menu arm.

import bank_auth.{
  type Message, type PaymentDetails, type Pin, type Statement, type Tan,
  type TransactionId,
}
import bank_auth/protocol/pin_tan_banking/customer
import eparch/state_machine
import gleam/erlang/process.{type Subject}
import gleam/result
import pacta/session/core.{type Channel}

/// A payment attempt after PIN authentication.
///
/// ## Example
///
/// ```gleam
/// let outcome = customer.Paid(bank_auth.TransactionId(1))
/// ```
///
pub type PaymentOutcome {
  Paid(TransactionId)
  RejectedTan(TransactionId)
}

/// Failures outside the selected local protocol.
///
/// ## Example
///
/// ```gleam
/// let failure = customer.PinRejected
/// ```
///
pub type Trouble {
  PinRejected
  NoAnswer
  Unexpected(Message)
}

const patience = 5000

/// Authenticate, request a statement, then log out.
///
/// ## Example
///
/// ```gleam
/// let assert Ok(bank_auth.Statement(balance: 100)) =
///   customer.statement(bank_auth.Pin("1234"), at: bank, from: inbox)
/// ```
///
pub fn statement(
  pin: Pin,
  at bank: state_machine.Started(Message),
  from inbox: Subject(Message),
) -> Result(Statement, Trouble) {
  authenticate(pin, bank, inbox, fn(channel) {
    let #(Nil, channel) = core.send(customer.banking_statement(channel), Nil)
    state_machine.cast(bank.ref, bank_auth.RequestStatement)

    use answer <- result.try(listen(inbox, channel))
    case answer {
      bank_auth.StatementReply(statement) -> {
        let channel = core.receive(customer.at_statement(channel), statement)
        use _ <- result.try(logout(channel, bank))
        Ok(statement)
      }
      other -> lost(channel, other)
    }
  })
}

/// Authenticate, run one TAN-protected payment, then log out.
///
/// The payment details are sent only on the successful TAN continuation. A
/// rejected TAN returns to the banking menu without a details message.
///
/// ## Example
///
/// ```gleam
/// let result = customer.pay(
///   bank_auth.Pin("1234"),
///   bank_auth.Tan("5678"),
///   bank_auth.PaymentDetails(to: "merchant", amount: 25),
///   at: bank,
///   from: inbox,
/// )
/// ```
///
pub fn pay(
  pin: Pin,
  tan: Tan,
  details: PaymentDetails,
  at bank: state_machine.Started(Message),
  from inbox: Subject(Message),
) -> Result(PaymentOutcome, Trouble) {
  authenticate(pin, bank, inbox, fn(channel) {
    let #(Nil, channel) = core.send(customer.banking_payment(channel), Nil)
    state_machine.cast(bank.ref, bank_auth.RequestPayment)

    use answer <- result.try(listen(inbox, channel))
    case answer {
      bank_auth.Transaction(id) -> {
        let channel = core.receive(customer.at_id(channel), id)
        authenticate_tan(id, tan, details, bank, inbox, channel)
      }
      other -> lost(channel, other)
    }
  })
}

fn authenticate(
  pin: Pin,
  bank: state_machine.Started(Message),
  inbox: Subject(Message),
  then continue: fn(Channel(customer.Banking, Message)) -> Result(a, Trouble),
) -> Result(a, Trouble) {
  let channel = customer.begin(bank.pid)
  let #(pin, channel) = core.send(customer.authenticating_pin(channel), pin)
  state_machine.cast(bank.ref, bank_auth.EnteredPin(pin))

  use answer <- result.try(listen(inbox, channel))
  case answer {
    bank_auth.PinAccepted ->
      continue(core.receive(customer.decision_ok(channel), Nil))

    bank_auth.PinRejected -> {
      let channel = core.receive(customer.decision_fail(channel), Nil)
      let _ = core.finish(customer.ended(channel))
      Error(PinRejected)
    }

    other -> lost(channel, other)
  }
}

fn authenticate_tan(
  id: TransactionId,
  tan: Tan,
  details: PaymentDetails,
  bank: state_machine.Started(Message),
  inbox: Subject(Message),
  channel: Channel(customer.AtTan, Message),
) -> Result(PaymentOutcome, Trouble) {
  let #(tan, channel) = core.send(customer.at_tan(channel), tan)
  state_machine.cast(bank.ref, bank_auth.EnteredTan(tan))

  use answer <- result.try(listen(inbox, channel))
  case answer {
    bank_auth.TanAccepted -> {
      let channel = core.receive(customer.decision2_ok(channel), Nil)
      let #(details, channel) = core.send(customer.at_details(channel), details)
      state_machine.cast(bank.ref, bank_auth.Details(details))
      use _ <- result.try(logout(channel, bank))
      Ok(Paid(id))
    }

    bank_auth.TanRejected -> {
      let channel = core.receive(customer.decision2_fail(channel), Nil)
      use _ <- result.try(logout(channel, bank))
      Ok(RejectedTan(id))
    }

    other -> lost(channel, other)
  }
}

fn logout(
  channel: Channel(customer.Banking, Message),
  bank: state_machine.Started(Message),
) -> Result(Nil, Trouble) {
  let #(Nil, channel) = core.send(customer.banking_logout(channel), Nil)
  state_machine.cast(bank.ref, bank_auth.Logout)
  let _ = core.finish(customer.ended(channel))
  Ok(Nil)
}

fn listen(
  inbox: Subject(Message),
  channel: Channel(protocol, Message),
) -> Result(Message, Trouble) {
  case process.receive(inbox, within: patience) {
    Ok(message) -> Ok(message)
    Error(Nil) -> {
      let _ = core.close(channel)
      Error(NoAnswer)
    }
  }
}

fn lost(
  channel: Channel(protocol, Message),
  said: Message,
) -> Result(a, Trouble) {
  let _ = core.close(channel)
  Error(Unexpected(said))
}
