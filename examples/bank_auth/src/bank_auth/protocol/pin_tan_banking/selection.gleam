//// The reviewed composition selection for `pin_tan_banking`.
////
//// Written by the bank-auth generator; manual edits are lost.
////
//// Source: Bocchi, Orchard and Voinea, Examples 1 and 2.
//// Branching mode: `Weak`.
//// Acceptance: one candidate from a complete search.
////
//// Required branching relaxations:
////
//// - arm `statement` could not compose and was left as it was
//// - arm `fail` could not compose and was left as it was
//// - arm `logout` could not compose and was left as it was
//// - arm `fail` could not compose and was left as it was
////

/// The branching mode used for this reviewed selection.
pub const branching = "Weak"
