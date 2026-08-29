////
//// The `Customer` view of the `pin_tan_banking` protocol, written by
//// `pacta/protocol/emit`.
////
//// Edits here are lost the next time it is generated. Change the specification
//// instead.
////
//// Each position below is an uninhabited type. The function named after it
//// unfolds it into the `pacta/session/core` shape the protocol says it has, one
//// step deep, and everything after that is an ordinary `core` or
//// `pacta/protocol_machine` call.
////

import bank_auth
import gleam/erlang/process.{type Pid}
import pacta/session/core.{type Channel}

// POSITIONS

/// Send `pin` to `Bank`, carrying `bank_auth.Pin`, then continue at `Decision`.
///
pub type AuthenticatingPin

/// `Bank` picks, so every arm needs a continuation:
///
/// - `ok` carrying `Nil`, then `Banking`
/// - `fail` carrying `Nil`, then `Ended`
///
pub type Decision

/// Pick one arm and tell `Bank` which:
///
/// - `statement` carrying `Nil`, then `AtStatement`
/// - `payment` carrying `Nil`, then `AtId`
/// - `logout` carrying `Nil`, then `Ended`
///
pub type Banking

/// The arms of `Banking` that are still open once the earlier ones have been
/// ruled out.
///
/// - `payment` carrying `Nil`, then `AtId`
/// - `logout` carrying `Nil`, then `Ended`
///
pub type BankingOtherwise

/// Accept `statement` from `Bank`, carrying `bank_auth.Statement`, then
/// continue at `Banking`.
///
pub type AtStatement

/// Accept `id` from `Bank`, carrying `bank_auth.TransactionId`, then continue
/// at `AtTan`.
///
pub type AtId

/// Send `tan` to `Bank`, carrying `bank_auth.Tan`, then continue at
/// `Decision2`.
///
pub type AtTan

/// `Bank` picks, so every arm needs a continuation:
///
/// - `ok` carrying `Nil`, then `AtDetails`
/// - `fail` carrying `Nil`, then `Banking`
///
pub type Decision2

/// Send `details` to `Bank`, carrying `bank_auth.PaymentDetails`, then continue
/// at `Banking`.
///
pub type AtDetails

/// Nothing is owed in either direction. A channel here can be closed with
/// `core.finish`, and nothing else.
///
pub type Ended

// OPENING

/// Open a channel to `peer` at the start of the protocol.
///
/// No monitor is installed. Call `core.watch` from the process that will own
/// the channel if this side needs to see the peer die.
///
pub fn begin(peer: Pid) -> Channel(AuthenticatingPin, msg) {
  core.begin(peer, protocol: "pin_tan_banking")
}

// UNFOLDING

/// Send `pin` to `Bank`, carrying `bank_auth.Pin`, then continue at `Decision`.
///
pub fn authenticating_pin(
  channel: Channel(AuthenticatingPin, msg),
) -> Channel(core.Send(bank_auth.Pin, Decision), msg) {
  core.unchecked_position(channel)
}

/// `Bank` picks, so every arm needs a continuation:
///
/// - `ok` carrying `Nil`, then `Banking`
/// - `fail` carrying `Nil`, then `Ended`
///
pub fn decision(
  channel: Channel(Decision, msg),
) -> Channel(core.Offer(core.Recv(Nil, Banking), core.Recv(Nil, Ended)), msg) {
  core.unchecked_position(channel)
}

/// Pick one arm and tell `Bank` which:
///
/// - `statement` carrying `Nil`, then `AtStatement`
/// - `payment` carrying `Nil`, then `AtId`
/// - `logout` carrying `Nil`, then `Ended`
///
pub fn banking(
  channel: Channel(Banking, msg),
) -> Channel(core.Choose(core.Send(Nil, AtStatement), BankingOtherwise), msg) {
  core.unchecked_position(channel)
}

/// The arms of `Banking` that are still open once the earlier ones have been
/// ruled out.
///
/// - `payment` carrying `Nil`, then `AtId`
/// - `logout` carrying `Nil`, then `Ended`
///
pub fn banking_otherwise(
  channel: Channel(BankingOtherwise, msg),
) -> Channel(core.Choose(core.Send(Nil, AtId), core.Send(Nil, Ended)), msg) {
  core.unchecked_position(channel)
}

/// Accept `statement` from `Bank`, carrying `bank_auth.Statement`, then
/// continue at `Banking`.
///
pub fn at_statement(
  channel: Channel(AtStatement, msg),
) -> Channel(core.Recv(bank_auth.Statement, Banking), msg) {
  core.unchecked_position(channel)
}

/// Accept `id` from `Bank`, carrying `bank_auth.TransactionId`, then continue
/// at `AtTan`.
///
pub fn at_id(
  channel: Channel(AtId, msg),
) -> Channel(core.Recv(bank_auth.TransactionId, AtTan), msg) {
  core.unchecked_position(channel)
}

/// Send `tan` to `Bank`, carrying `bank_auth.Tan`, then continue at
/// `Decision2`.
///
pub fn at_tan(
  channel: Channel(AtTan, msg),
) -> Channel(core.Send(bank_auth.Tan, Decision2), msg) {
  core.unchecked_position(channel)
}

/// `Bank` picks, so every arm needs a continuation:
///
/// - `ok` carrying `Nil`, then `AtDetails`
/// - `fail` carrying `Nil`, then `Banking`
///
pub fn decision2(
  channel: Channel(Decision2, msg),
) -> Channel(
  core.Offer(core.Recv(Nil, AtDetails), core.Recv(Nil, Banking)),
  msg,
) {
  core.unchecked_position(channel)
}

/// Send `details` to `Bank`, carrying `bank_auth.PaymentDetails`, then continue
/// at `Banking`.
///
pub fn at_details(
  channel: Channel(AtDetails, msg),
) -> Channel(core.Send(bank_auth.PaymentDetails, Banking), msg) {
  core.unchecked_position(channel)
}

/// Nothing is owed in either direction. A channel here can be closed with
/// `core.finish`, and nothing else.
///
pub fn ended(channel: Channel(Ended, msg)) -> Channel(core.Done, msg) {
  core.unchecked_position(channel)
}

// CHOICES

/// Follow the `ok` arm of `Decision`, which continues at `Banking`.
///
pub fn decision_ok(
  channel: Channel(Decision, msg),
) -> Channel(core.Recv(Nil, Banking), msg) {
  channel |> decision |> core.offered_left
}

/// Follow the `fail` arm of `Decision`, which continues at `Ended`.
///
pub fn decision_fail(
  channel: Channel(Decision, msg),
) -> Channel(core.Recv(Nil, Ended), msg) {
  channel |> decision |> core.offered_right
}

/// Take the `statement` arm of `Banking`, which continues at `AtStatement`.
///
pub fn banking_statement(
  channel: Channel(Banking, msg),
) -> Channel(core.Send(Nil, AtStatement), msg) {
  channel |> banking |> core.choose_left
}

/// Take the `payment` arm of `Banking`, which continues at `AtId`.
///
pub fn banking_payment(
  channel: Channel(Banking, msg),
) -> Channel(core.Send(Nil, AtId), msg) {
  channel
  |> banking
  |> core.choose_right
  |> banking_otherwise
  |> core.choose_left
}

/// Take the `logout` arm of `Banking`, which continues at `Ended`.
///
pub fn banking_logout(
  channel: Channel(Banking, msg),
) -> Channel(core.Send(Nil, Ended), msg) {
  channel
  |> banking
  |> core.choose_right
  |> banking_otherwise
  |> core.choose_right
}

/// Follow the `ok` arm of `Decision2`, which continues at `AtDetails`.
///
pub fn decision2_ok(
  channel: Channel(Decision2, msg),
) -> Channel(core.Recv(Nil, AtDetails), msg) {
  channel |> decision2 |> core.offered_left
}

/// Follow the `fail` arm of `Decision2`, which continues at `Banking`.
///
pub fn decision2_fail(
  channel: Channel(Decision2, msg),
) -> Channel(core.Recv(Nil, Banking), msg) {
  channel |> decision2 |> core.offered_right
}
