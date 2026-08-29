////
//// Tests for interleaving composition.
////
//// The examples are Bocchi, Orchard and Voinea's, which makes them worth more
//// than tests written to fit the implementation: the paper states what each
//// composition should produce, and their Table 1 states how many compositions
//// each branching rule should find. Several tests below check counts against
//// that table, which is the closest thing available to an oracle.
////

import gleam/int
import gleam/list
import pacta/protocol/graph
import pacta/protocol/spec
import pacta/protocol/weave

// HELPERS

fn tell(label: String, then: spec.Spec) -> spec.Spec {
  spec.Message(from: "A", to: "B", label:, payload: "Nil", then:)
}

fn arm(label: String, then: spec.Spec) -> spec.Branch {
  spec.Branch(label:, payload: "Nil", then:)
}

fn pick(branches: List(spec.Branch)) -> spec.Spec {
  spec.Choice(at: "A", to: "B", branches:)
}

fn directed_pick(
  at at: String,
  to to: String,
  branches branches: List(spec.Branch),
) -> spec.Spec {
  spec.Choice(at:, to:, branches:)
}

fn directed_tell(
  from from: String,
  to to: String,
  label label: String,
  then then: spec.Spec,
) -> spec.Spec {
  spec.Message(from:, to:, label:, payload: "Nil", then:)
}

fn using(branching: weave.Branching) -> weave.Options {
  weave.Options(..weave.defaults(), branching:)
}

fn count(left: spec.Spec, right: spec.Spec, branching: weave.Branching) -> Int {
  let weave.Composition(candidates:, truncated: _) =
    weave.compose(left, right, using(branching))

  list.length(candidates)
}

fn protocols(
  left: spec.Spec,
  right: spec.Spec,
  branching: weave.Branching,
) -> List(spec.Spec) {
  let weave.Composition(candidates:, truncated: _) =
    weave.compose(left, right, using(branching))

  list.map(candidates, fn(candidate) { candidate.protocol })
}

fn erase_contacts(protocol: spec.Spec) -> spec.Spec {
  case protocol {
    spec.At(name:, then:) -> spec.At(name:, then: erase_contacts(then))
    spec.Message(from:, to:, label:, payload:, then:) ->
      spec.Message(from:, to:, label:, payload:, then: erase_contacts(then))
    spec.Choice(at:, to:, branches:) ->
      spec.Choice(
        at:,
        to:,
        branches: list.map(branches, fn(branch) {
          spec.Branch(..branch, then: erase_contacts(branch.then))
        }),
      )
    spec.Loop(name:, body:) -> spec.Loop(name:, body: erase_contacts(body))
    spec.Continue(name) -> spec.Continue(name)
    spec.Assert(name: _, then:)
    | spec.Require(name: _, then:)
    | spec.Consume(name: _, then:) -> erase_contacts(then)
    spec.End -> spec.End
  }
}

fn executable_protocol_count(
  left: spec.Spec,
  right: spec.Spec,
  branching: weave.Branching,
) -> Int {
  protocols(left, right, branching)
  |> list.map(erase_contacts)
  |> list.unique
  |> list.length
}

// SEQUENCES
//
// Two protocols with nothing to say about each other can be woven either way
// round. This is the base case that everything else constrains.

pub fn two_unconstrained_actions_weave_both_ways_test() -> Nil {
  let found =
    protocols(tell("pay", spec.End), tell("item", spec.End), weave.Strong)

  assert found
    == [
      tell("pay", tell("item", spec.End)),
      tell("item", tell("pay", spec.End)),
    ]
}

pub fn contact_points_pin_the_order_test() -> Nil {
  // The paper's Section 2.1 example. Payment asserts that it happened;
  // dispatch consumes that guarantee, so dispatch cannot come first.
  let paying = tell("pay", spec.Assert("paid", spec.End))
  let dispatching = spec.Consume("paid", tell("item", spec.End))

  assert protocols(paying, dispatching, weave.Strong)
    == [
      tell(
        "pay",
        spec.Assert("paid", spec.Consume("paid", tell("item", spec.End))),
      ),
    ]
}

pub fn a_requirement_nothing_supplies_weaves_into_nothing_test() -> Nil {
  let needing = spec.Require("pin", tell("balance", spec.End))

  assert count(needing, tell("hello", spec.End), weave.Strong) == 0
}

pub fn a_requirement_survives_being_met_test() -> Nil {
  // Non-linear, so one assertion covers two requirements. Both orderings of
  // the two requiring actions remain available.
  let granting = tell("login", spec.Assert("pin", spec.End))
  let using_it =
    spec.Require(
      "pin",
      tell("balance", spec.Require("pin", tell("statement", spec.End))),
    )

  assert count(granting, using_it, weave.Strong) == 1
}

// BRANCHING
//
// Composing after a choice distributes into the arms, which is what makes the
// branching rule a distributivity property.

pub fn composing_with_a_choice_distributes_into_every_arm_test() -> Nil {
  // The paper's example under rule [bra]: two interleavings, one where the
  // action is pushed inside both arms and one where it comes first.
  let choosing = pick([arm("l1", spec.End), arm("l2", spec.End)])
  let acting = tell("send", spec.End)

  let found = protocols(choosing, acting, weave.Strong)

  assert list.length(found) == 2
  assert list.contains(
    found,
    pick([arm("l1", tell("send", spec.End)), arm("l2", tell("send", spec.End))]),
  )
  assert list.contains(
    found,
    tell("send", pick([arm("l1", spec.End), arm("l2", spec.End)])),
  )
}

pub fn an_arm_that_cannot_compose_stops_strong_branching_test() -> Nil {
  // Authentication grants the guarantee in one arm only, so the service
  // cannot be composed into the other. Strong branching has no answer.
  let authenticating =
    tell(
      "password",
      pick([arm("ok", spec.Assert("access", spec.End)), arm("no", spec.End)]),
    )
  let serving = spec.Require("access", tell("balance", spec.End))

  assert count(authenticating, serving, weave.Strong) == 0
}

pub fn weak_branching_leaves_the_arm_that_cannot_compose_alone_test() -> Nil {
  let authenticating =
    tell(
      "password",
      pick([arm("ok", spec.Assert("access", spec.End)), arm("no", spec.End)]),
    )
  let serving = spec.Require("access", tell("balance", spec.End))

  // Exactly the protocol the paper derives: the service happens after a
  // successful login and not at all after a failed one.
  assert protocols(authenticating, serving, weave.Weak)
    == [
      tell(
        "password",
        pick([
          arm(
            "ok",
            spec.Assert(
              "access",
              spec.Require("access", tell("balance", spec.End)),
            ),
          ),
          arm("no", spec.End),
        ]),
      ),
    ]
}

pub fn table_1_row_1_service_and_login_counts_test() -> Nil {
  // Section 3.1.1 leaves S' abstract. Its first ordinary action is sufficient
  // to reproduce the branching derivations counted in Table 1, row 1.
  let login =
    tell(
      "pwd",
      pick([arm("ok", spec.Assert("n", spec.End)), arm("ko", spec.End)]),
    )
  let service = spec.Require("n", tell("service", spec.End))

  assert count(service, login, weave.Strong) == 0
  assert count(service, login, weave.Weak) == 1
  assert count(service, login, weave.Correlating) == 0
  assert count(service, login, weave.All) == 1
}

pub fn weak_branching_records_the_liberty_it_took_test() -> Nil {
  let authenticating =
    tell(
      "password",
      pick([arm("ok", spec.Assert("access", spec.End)), arm("no", spec.End)]),
    )
  let serving = spec.Require("access", tell("balance", spec.End))

  let assert weave.Composition(candidates: [only], ..) =
    weave.compose(authenticating, serving, using(weave.Weak))

  assert only.relaxations == [weave.WeakBranch("no")]
  assert weave.summarise(only) != "derivable with strong branching"
}

pub fn weak_branching_cannot_drop_a_protocol_entirely_test() -> Nil {
  // Nothing establishes the guarantee, so no arm composes. Leaving every arm
  // alone would silently discard the second protocol, which is what the
  // "at least one arm composes" condition prevents.
  let choosing = pick([arm("l1", spec.End), arm("l2", spec.End)])
  let needing = spec.Require("access", tell("balance", spec.End))

  assert count(choosing, needing, weave.Weak) == 0
}

// CORRELATING BRANCHING
//
// Section 3.1.2 of the paper, and the row of Table 1 that exercises all three
// rules at once.

fn services() -> spec.Spec {
  pick([
    arm("service_one", spec.Assert("one", spec.End)),
    arm("service_two", spec.Assert("two", spec.End)),
  ])
}

fn payments() -> spec.Spec {
  pick([
    arm("pay_one", spec.Consume("one", spec.End)),
    arm("pay_two", spec.Consume("two", spec.End)),
  ])
}

pub fn correlating_branching_pairs_arms_off_test() -> Nil {
  let found = protocols(services(), payments(), weave.Correlating)

  // Each service is paired with the payment it enables, and with no other. A
  // one-armed choice is just a labelled message, which is what it becomes.
  assert list.contains(
    found,
    pick([
      arm(
        "service_one",
        tell_labelled(
          "pay_one",
          spec.Assert("one", spec.Consume("one", spec.End)),
        ),
      ),
      arm(
        "service_two",
        tell_labelled(
          "pay_two",
          spec.Assert("two", spec.Consume("two", spec.End)),
        ),
      ),
    ]),
  )
}

fn tell_labelled(label: String, then: spec.Spec) -> spec.Spec {
  spec.Message(from: "A", to: "B", label:, payload: "Nil", then:)
}

pub fn the_branching_rules_find_what_the_paper_counts_test() -> Nil {
  // Table 1, row 2. The counts are the paper's, not the implementation's, so
  // this is the closest thing to an oracle these rules have.
  assert count(services(), payments(), weave.Strong) == 0
  assert count(services(), payments(), weave.Weak) == 1
  assert count(services(), payments(), weave.Correlating) == 2
  assert count(services(), payments(), weave.All) == 3
}

pub fn relaxations_never_lose_a_candidate_test() -> Nil {
  // Table 1, row 3: the payment example is derivable strongly, so every looser
  // rule still finds it. Each relaxation widens the set rather than replacing
  // it.
  let paying = tell("pay", spec.Assert("paid", spec.End))
  let dispatching = spec.Consume("paid", tell("item", spec.End))

  let strong = protocols(paying, dispatching, weave.Strong)

  assert list.length(strong) == 1
  assert count(paying, dispatching, weave.Weak) == 1
  assert count(paying, dispatching, weave.Correlating) == 1
  assert count(paying, dispatching, weave.All) == 1
}

fn agent_instrument() -> spec.Spec {
  // Appendix B.3's first asserted protocol, the agent acting as a client of
  // the instrument. Pacta records each local action as its global direction.
  spec.Loop(
    "instrument",
    directed_pick(at: "Agent", to: "Instrument", branches: [
      arm(
        "set",
        spec.Consume(
          "set",
          spec.Consume(
            "forward",
            directed_tell(
              from: "Agent",
              to: "Instrument",
              label: "coord",
              then: spec.Continue("instrument"),
            ),
          ),
        ),
      ),
      arm(
        "get",
        spec.Consume(
          "get",
          directed_tell(
            from: "Instrument",
            to: "Agent",
            label: "snap",
            then: spec.Assert("forward", spec.Continue("instrument")),
          ),
        ),
      ),
    ]),
  )
}

fn user_agent() -> spec.Spec {
  // Appendix B.3's second asserted protocol, the agent acting as a server for
  // the user. The user's choice supplies the assertion paired above.
  spec.Loop(
    "user",
    directed_pick(at: "User", to: "Agent", branches: [
      arm(
        "set",
        spec.Assert(
          "set",
          directed_tell(
            from: "User",
            to: "Agent",
            label: "coord",
            then: spec.Assert("forward", spec.Continue("user")),
          ),
        ),
      ),
      arm(
        "get",
        spec.Assert(
          "get",
          spec.Consume(
            "forward",
            directed_tell(
              from: "Agent",
              to: "User",
              label: "snap",
              then: spec.Continue("user"),
            ),
          ),
        ),
      ),
    ]),
  )
}

pub fn table_1_row_9_multiparty_proxy_counts_test() -> Nil {
  // These are the role-explicit protocols printed in Appendix B.3. Unlike the
  // two-party examples above, no placeholder roles are needed. Pacta retains
  // three placements of the consumed `set` evidence for each executable
  // ordering, while the paper's count omits that evidence. All six candidates
  // therefore collapse to the paper's two protocols at the executable layer.
  assert count(user_agent(), agent_instrument(), weave.Strong) == 0
  assert count(user_agent(), agent_instrument(), weave.Weak) == 0
  assert count(user_agent(), agent_instrument(), weave.Correlating) == 6
  assert count(user_agent(), agent_instrument(), weave.All) == 6
  assert executable_protocol_count(
      user_agent(),
      agent_instrument(),
      weave.Correlating,
    )
    == 2
  assert executable_protocol_count(user_agent(), agent_instrument(), weave.All)
    == 2
}

pub fn candidates_needing_no_liberties_come_first_test() -> Nil {
  let weave.Composition(candidates:, truncated: _) =
    weave.compose(services(), payments(), using(weave.All))

  let taken =
    list.map(candidates, fn(candidate) { list.length(candidate.relaxations) })

  assert taken == list.sort(taken, by: int.compare)
}

// RECURSION
//
// Two loops become one loop, and a loop must not swallow a protocol that was
// written to happen once.

fn repeating(label: String, name: String) -> spec.Spec {
  spec.Loop(name, tell(label, spec.Continue(name)))
}

pub fn two_loops_merge_into_one_test() -> Nil {
  let found =
    protocols(repeating("ping", "a"), repeating("pong", "b"), weave.Strong)

  // One binder survives, and both actions happen inside it. Weavings that
  // differ only in which binder survived are the same weaving.
  assert list.length(found) == 2
  list.each(found, fn(candidate) {
    let assert spec.Loop(name: _, body: _) = candidate
  })
}

pub fn a_loop_cannot_swallow_a_protocol_written_to_happen_once_test() -> Nil {
  // The undesirable composition the paper rules out: a loop that repeats an
  // action its author wrote exactly once. What is left is the one weaving
  // where the finite protocol finishes first.
  let looping = repeating("poll", "a")
  let once = tell("setup", spec.End)

  assert protocols(looping, once, weave.Strong)
    == [tell("setup", repeating("poll", "a"))]
}

pub fn a_loop_alone_with_an_ending_protocol_still_weaves_test() -> Nil {
  let found = protocols(repeating("poll", "a"), spec.End, weave.Strong)

  assert found == [repeating("poll", "a")]
}

// RESULTS ARE ORDINARY PROTOCOLS
//
// The reason interleaving belongs here rather than in the type system: what
// comes out is the same thing that went in, so everything else still applies.

pub fn a_weaving_is_a_protocol_that_still_projects_test() -> Nil {
  let authenticating =
    tell(
      "password",
      pick([arm("ok", spec.Assert("access", spec.End)), arm("no", spec.End)]),
    )
  let serving = spec.Require("access", tell("balance", spec.End))

  let assert [best, ..] =
    weave.interleave(
      wrap("banking", authenticating),
      wrap("auth", serving),
      using(weave.Weak),
    )

  let assert Ok([_a, _b]) = graph.compile(best)
  Nil
}

pub fn interleaving_keeps_the_participants_of_both_test() -> Nil {
  let here = spec.Message("A", "B", "x", "Nil", spec.End)
  let there = spec.Message("B", "C", "y", "Nil", spec.End)

  let assert [best, ..] =
    weave.interleave(
      spec.Protocol("here", ["A", "B"], "Start", ["import a"], here),
      spec.Protocol("there", ["B", "C"], "Start", ["import b"], there),
      using(weave.Strong),
    )

  assert best.roles == ["A", "B", "C"]
  assert best.imports == ["import a", "import b"]
}

fn wrap(name: String, body: spec.Spec) -> spec.Protocol {
  spec.Protocol(
    name:,
    roles: ["A", "B"],
    initial: "Start",
    imports: [],
    spec: body,
  )
}

// LIMITS

pub fn the_search_says_when_it_stopped_looking_test() -> Nil {
  let weave.Composition(candidates:, truncated:) =
    weave.compose(
      tell("a", tell("b", tell("c", spec.End))),
      tell("x", tell("y", tell("z", spec.End))),
      weave.Options(..weave.defaults(), limit: 2),
    )

  assert truncated == True
  assert list.length(candidates) <= 2
}

pub fn nothing_is_hidden_when_the_search_finishes_test() -> Nil {
  let weave.Composition(candidates: _, truncated:) =
    weave.compose(tell("a", spec.End), tell("x", spec.End), weave.defaults())

  assert truncated == False
}

pub fn a_complete_unique_candidate_can_be_selected_test() -> Nil {
  let composition =
    weave.compose(
      tell("pay", spec.Assert("paid", spec.End)),
      spec.Consume("paid", tell("item", spec.End)),
      weave.defaults(),
    )

  let assert Ok(weave.Candidate(protocol:, relaxations: [])) =
    weave.select_unique(composition)
  assert protocol
    == tell(
      "pay",
      spec.Assert("paid", spec.Consume("paid", tell("item", spec.End))),
    )
}

pub fn selecting_rejects_an_empty_or_ambiguous_search_test() -> Nil {
  let first = weave.Candidate(tell("first", spec.End), [])
  let second = weave.Candidate(tell("second", spec.End), [])

  assert weave.select_unique(weave.Composition([], False))
    == Error(weave.UnexpectedCandidateCount(0))
  assert weave.select_unique(weave.Composition([first, second], False))
    == Error(weave.UnexpectedCandidateCount(2))
}

pub fn selecting_rejects_truncation_before_counting_candidates_test() -> Nil {
  let candidate = weave.Candidate(tell("found", spec.End), [])

  assert weave.select_unique(weave.Composition([candidate], True))
    == Error(weave.SearchTruncated)
}
