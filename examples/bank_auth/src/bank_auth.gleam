//// Domain values used by the composed PIN/TAN banking example.
////
//// The paper leaves these payload domains abstract. The concrete fields here
//// make the generated protocol executable; the protocol depends on their
//// types, not on these representations.

/// The customer's personal identification number.
///
/// ## Example
///
/// ```gleam
/// let pin = bank_auth.Pin("1234")
/// ```
///
pub type Pin {
  Pin(String)
}

/// A one-time transaction authentication number.
///
/// ## Example
///
/// ```gleam
/// let tan = bank_auth.Tan("5678")
/// ```
///
pub type Tan {
  Tan(String)
}

/// The identifier issued for one payment authentication attempt.
///
/// ## Example
///
/// ```gleam
/// let id = bank_auth.TransactionId(1)
/// ```
///
pub type TransactionId {
  TransactionId(Int)
}

/// Details of the payment authorised by a TAN.
///
/// ## Example
///
/// ```gleam
/// let details = bank_auth.PaymentDetails(to: "merchant", amount: 25)
/// ```
///
pub type PaymentDetails {
  PaymentDetails(to: String, amount: Int)
}

/// A banking statement returned to the customer.
///
/// ## Example
///
/// ```gleam
/// let statement = bank_auth.Statement(balance: 100)
/// ```
///
pub type Statement {
  Statement(balance: Int)
}

/// Every message exchanged by the customer and bank.
///
/// Branch labels become nullary messages, while payload actions carry the
/// domain values above.
///
/// ## Example
///
/// ```gleam
/// let message = bank_auth.EnteredPin(bank_auth.Pin("1234"))
/// ```
///
pub type Message {
  EnteredPin(Pin)
  PinAccepted
  PinRejected
  RequestStatement
  RequestPayment
  Logout
  StatementReply(Statement)
  Transaction(TransactionId)
  EnteredTan(Tan)
  TanAccepted
  TanRejected
  Details(PaymentDetails)
  /// Internal event used to drive positions where the bank must send.
  Proceed
}
