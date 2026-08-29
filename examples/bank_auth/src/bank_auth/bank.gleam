//// The bank side of the paper's composed PIN/TAN banking protocol.
////
//// This is a typed `gen_statem` implementation of SBA from Example 2. Every
//// function below owns one generated position. In particular, payment details
//// are unreachable until the machine has selected the successful TAN arm.

import bank_auth.{
  type Message, type Pin, type Tan, Details, EnteredPin, EnteredTan, Logout,
  PinAccepted, PinRejected, Proceed, RequestPayment, RequestStatement, Statement,
  StatementReply, TanAccepted, TanRejected, Transaction, TransactionId,
}
import bank_auth/protocol/pin_tan_banking/bank
import eparch/state_machine
import gleam/erlang/process.{type Subject}
import pacta/protocol_machine as pm
import pacta/session/core.{type Channel}

/// The small runtime tags visible in OTP diagnostics.
///
/// ## Example
///
/// ```gleam
/// let tag = bank.AuthenticatingPin
/// ```
///
pub type Tag {
  AuthenticatingPin
  DecidingPin
  Banking
  SendingStatement
  IssuingTransaction
  AuthenticatingTan
  DecidingTan
  AcceptingDetails
  Closing
}

type Account {
  Account(balance: Int, next_id: Int)
}

type Settings {
  Settings(customer: Subject(Message), pin: Pin, tan: Tan)
}

type Position(protocol) =
  pm.ProtocolState(protocol, Tag, Account, Message, Nil)

/// Start a bank using the PIN and TAN expected by this session.
///
/// The paper leaves payload representations and credential checking abstract.
/// This executable instance compares the supplied values structurally and
/// starts transaction identifiers at one.
///
/// ## Example
///
/// ```gleam
/// let inbox = process.new_subject()
/// let assert Ok(started) = bank.start(
///   serving: inbox,
///   pin: bank_auth.Pin("1234"),
///   tan: bank_auth.Tan("5678"),
///   balance: 100,
/// )
/// ```
///
pub fn start(
  serving customer: Subject(Message),
  pin pin: Pin,
  tan tan: Tan,
  balance balance: Int,
) -> state_machine.StartResult(Message) {
  let settings = Settings(customer:, pin:, tan:)
  let account = Account(balance:, next_id: 1)

  at_authenticating_pin(bank.begin(process.self()), account, settings)
  |> pm.new
  |> pm.start_link
}

fn at_authenticating_pin(
  channel: Channel(bank.AuthenticatingPin, Message),
  account: Account,
  settings: Settings,
) -> Position(bank.AuthenticatingPin) {
  pm.state(
    tag: AuthenticatingPin,
    at: channel,
    data: account,
    handler: fn(event, channel, account) {
      case event {
        state_machine.Cast(EnteredPin(supplied)) ->
          pm.along(
            at: channel,
            route: bank.authenticating_pin,
            step: fn(channel) {
              pm.accept(
                at: channel,
                message: supplied,
                actions: [pm.advance_now(Proceed)],
                then: fn(next) {
                  at_pin_decision(
                    next,
                    account,
                    settings,
                    supplied == settings.pin,
                  )
                },
              )
            },
          )

        _ -> pm.postpone()
      }
    },
  )
}

fn at_pin_decision(
  channel: Channel(bank.Decision, Message),
  account: Account,
  settings: Settings,
  approved: Bool,
) -> Position(bank.Decision) {
  pm.state(
    tag: DecidingPin,
    at: channel,
    data: account,
    handler: fn(event, channel, account) {
      case event, approved {
        state_machine.Cast(Proceed), True ->
          pm.along(at: channel, route: bank.decision_ok, step: fn(channel) {
            pm.transmit(
              at: channel,
              message: Nil,
              actions: [],
              then: fn(_label, next) {
                process.send(settings.customer, PinAccepted)
                at_banking(next, account, settings)
              },
            )
          })

        state_machine.Cast(Proceed), False ->
          pm.along(at: channel, route: bank.decision_fail, step: fn(channel) {
            pm.transmit(
              at: channel,
              message: Nil,
              actions: [pm.advance_now(Proceed)],
              then: fn(_label, next) {
                process.send(settings.customer, PinRejected)
                at_ended(next, account)
              },
            )
          })

        _, _ -> pm.postpone()
      }
    },
  )
}

fn at_banking(
  channel: Channel(bank.Banking, Message),
  account: Account,
  settings: Settings,
) -> Position(bank.Banking) {
  pm.state(
    tag: Banking,
    at: channel,
    data: account,
    handler: fn(event, channel, account) {
      case event {
        state_machine.Cast(RequestStatement) ->
          pm.along(
            at: channel,
            route: bank.banking_statement,
            step: fn(channel) {
              pm.accept(
                at: channel,
                message: Nil,
                actions: [pm.advance_now(Proceed)],
                then: fn(next) { at_statement(next, account, settings) },
              )
            },
          )

        state_machine.Cast(RequestPayment) ->
          pm.along(at: channel, route: bank.banking_payment, step: fn(channel) {
            pm.accept(
              at: channel,
              message: Nil,
              actions: [pm.advance_now(Proceed)],
              then: fn(next) { at_id(next, account, settings) },
            )
          })

        state_machine.Cast(Logout) ->
          pm.along(at: channel, route: bank.banking_logout, step: fn(channel) {
            pm.accept(
              at: channel,
              message: Nil,
              actions: [pm.advance_now(Proceed)],
              then: fn(next) { at_ended(next, account) },
            )
          })

        _ -> pm.postpone()
      }
    },
  )
}

fn at_statement(
  channel: Channel(bank.AtStatement, Message),
  account: Account,
  settings: Settings,
) -> Position(bank.AtStatement) {
  pm.state(
    tag: SendingStatement,
    at: channel,
    data: account,
    handler: fn(event, channel, account) {
      case event {
        state_machine.Cast(Proceed) ->
          pm.along(at: channel, route: bank.at_statement, step: fn(channel) {
            pm.transmit(
              at: channel,
              message: Statement(balance: account.balance),
              actions: [],
              then: fn(statement, next) {
                process.send(settings.customer, StatementReply(statement))
                at_banking(next, account, settings)
              },
            )
          })

        _ -> pm.postpone()
      }
    },
  )
}

fn at_id(
  channel: Channel(bank.AtId, Message),
  account: Account,
  settings: Settings,
) -> Position(bank.AtId) {
  pm.state(
    tag: IssuingTransaction,
    at: channel,
    data: account,
    handler: fn(event, channel, account) {
      case event {
        state_machine.Cast(Proceed) ->
          pm.along(at: channel, route: bank.at_id, step: fn(channel) {
            let id = TransactionId(account.next_id)
            pm.transmit(
              at: channel,
              message: id,
              actions: [],
              then: fn(checked, next) {
                process.send(settings.customer, Transaction(checked))
                at_tan(next, account, settings)
              },
            )
          })

        _ -> pm.postpone()
      }
    },
  )
}

fn at_tan(
  channel: Channel(bank.AtTan, Message),
  account: Account,
  settings: Settings,
) -> Position(bank.AtTan) {
  pm.state(
    tag: AuthenticatingTan,
    at: channel,
    data: account,
    handler: fn(event, channel, account) {
      case event {
        state_machine.Cast(EnteredTan(supplied)) ->
          pm.along(at: channel, route: bank.at_tan, step: fn(channel) {
            pm.accept(
              at: channel,
              message: supplied,
              actions: [pm.advance_now(Proceed)],
              then: fn(next) {
                at_tan_decision(
                  next,
                  account,
                  settings,
                  supplied == settings.tan,
                )
              },
            )
          })

        _ -> pm.postpone()
      }
    },
  )
}

fn at_tan_decision(
  channel: Channel(bank.Decision2, Message),
  account: Account,
  settings: Settings,
  approved: Bool,
) -> Position(bank.Decision2) {
  pm.state(
    tag: DecidingTan,
    at: channel,
    data: account,
    handler: fn(event, channel, account) {
      case event, approved {
        state_machine.Cast(Proceed), True ->
          pm.along(at: channel, route: bank.decision2_ok, step: fn(channel) {
            pm.transmit(
              at: channel,
              message: Nil,
              actions: [],
              then: fn(_label, next) {
                process.send(settings.customer, TanAccepted)
                at_details(next, account, settings)
              },
            )
          })

        state_machine.Cast(Proceed), False ->
          pm.along(at: channel, route: bank.decision2_fail, step: fn(channel) {
            pm.transmit(
              at: channel,
              message: Nil,
              actions: [],
              then: fn(_label, next) {
                process.send(settings.customer, TanRejected)
                at_banking(next, account, settings)
              },
            )
          })

        _, _ -> pm.postpone()
      }
    },
  )
}

fn at_details(
  channel: Channel(bank.AtDetails, Message),
  account: Account,
  settings: Settings,
) -> Position(bank.AtDetails) {
  pm.state(
    tag: AcceptingDetails,
    at: channel,
    data: account,
    handler: fn(event, channel, account) {
      case event {
        state_machine.Cast(Details(details)) ->
          pm.along(at: channel, route: bank.at_details, step: fn(channel) {
            pm.accept(
              at: channel,
              message: details,
              actions: [],
              then: fn(next) {
                at_banking(
                  next,
                  Account(
                    balance: account.balance - details.amount,
                    next_id: account.next_id + 1,
                  ),
                  settings,
                )
              },
            )
          })

        _ -> pm.postpone()
      }
    },
  )
}

fn at_ended(
  channel: Channel(bank.Ended, Message),
  account: Account,
) -> Position(bank.Ended) {
  pm.state(
    tag: Closing,
    at: channel,
    data: account,
    handler: fn(event, channel, _account) {
      case event {
        state_machine.Cast(Proceed) ->
          pm.along(at: channel, route: bank.ended, step: fn(channel) {
            pm.complete(at: channel, actions: [])
          })

        _ -> pm.postpone()
      }
    },
  )
}
