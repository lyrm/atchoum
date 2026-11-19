(** Merlin queries, run through the [ocamlmerlin] executable found in [PATH]. *)

[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type position = { line : int;  (** From 1. *) col : int  (** From 0. *) }

type location = { file : string; pos : position }
(** Where a definition is. [file] is as Merlin reports it, usually absolute. *)

val type_enclosing :
  fs:_ Eio.Path.t ->
  process_mgr:_ Eio.Process.mgr ->
  file:string ->
  line:int ->
  col:int ->
  (string, string) result
(** [type_enclosing ~fs ~process_mgr ~file ~line ~col] runs
    [ocamlmerlin single type-enclosing -position LINE:COL -filename FILE] with
    the contents of [file] on standard input. [line] starts at 1 and [col] at 0.
    A relative [file] is resolved against the current working directory.

    Returns [Ok ty], the type of the innermost expression at the position.
    Returns [Error msg] when there is no expression there, when Merlin fails
    (its message is in [msg]), or when [file] or [ocamlmerlin] cannot be found.
*)

val locate :
  fs:_ Eio.Path.t ->
  process_mgr:_ Eio.Process.mgr ->
  ?prefix:string ->
  ?look_for:[ `Interface | `Implementation ] ->
  file:string ->
  line:int ->
  col:int ->
  unit ->
  (location, string) result
(** [locate ~fs ~process_mgr ?prefix ?look_for ~file ~line ~col ()] runs
    [ocamlmerlin single locate -position LINE:COL -filename FILE] with the
    contents of [file] on standard input, to find where the identifier at
    [line]:[col] is defined.

    With [prefix], Merlin locates that identifier (possibly qualified, such as
    [List.map]) instead of the one at the position; the position still sets the
    scope. [look_for] prefers the interface or the implementation.

    Returns [Error reason] when Merlin cannot find the definition (for instance
    ["Not in environment 'x'"]), and otherwise fails as {!type_enclosing}. *)
