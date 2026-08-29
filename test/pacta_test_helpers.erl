-module(pacta_test_helpers).
-moduledoc """
Test-only helpers used by `protocol_machine_test.gleam` and
`protocol_generated_test.gleam`. Pure encoding glue: reach the Erlang-shape
values that Gleam cannot express through its own type system.
""".

-export([
    sys_get_status_text/1
]).

-doc """
Render `sys:get_status/1` as text so Gleam can assert against it.

The status is a deeply nested Erlang term with no stable Gleam shape, so
formatting it here is cheaper than decoding it. Used to check that the
`gen_statem` state really is the protocol tag.
""".
sys_get_status_text(Pid) ->
    unicode:characters_to_binary(io_lib:format("~p", [sys:get_status(Pid)])).
