(** Merlin queries, run through the [ocamlmerlin] executable found in [PATH].

    Every query runs [ocamlmerlin single COMMAND ... -filename FILE] with the
    contents of [file] on standard input, and decodes the useful part of the
    answer. A relative [file] is resolved against the current working directory.
    Lines start at 1 and columns at 0.

    Every query returns [Error msg] when Merlin fails (its message is in [msg]),
    or when [file] or [ocamlmerlin] cannot be found. *)

[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type position = { line : int;  (** From 1. *) col : int  (** From 0. *) }
type range = { start : position; stop : position }

type location = { file : string; pos : position }
(** Where a definition is. [file] is as Merlin reports it, usually absolute. *)

val type_enclosing :
  fs:_ Eio.Path.t ->
  process_mgr:_ Eio.Process.mgr ->
  ?expand:bool ->
  file:string ->
  line:int ->
  col:int ->
  unit ->
  (string, string) result
(** The type of the innermost expression at the position. With [expand], module
    types and type abbreviations are expanded one level (the signature of a
    module path, for instance). *)

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
(** Where the identifier at the position, or [prefix] in the position's scope,
    is defined. [look_for] prefers the interface or the implementation.
    [Error reason] when Merlin cannot find it. *)

val locate_type :
  fs:_ Eio.Path.t ->
  process_mgr:_ Eio.Process.mgr ->
  file:string ->
  line:int ->
  col:int ->
  (location, string) result
(** Where the type of the expression at the position is defined. *)

val document :
  fs:_ Eio.Path.t ->
  process_mgr:_ Eio.Process.mgr ->
  file:string ->
  line:int ->
  col:int ->
  (string, string) result
(** The documentation comment of the identifier at the position. *)

val type_expression :
  fs:_ Eio.Path.t ->
  process_mgr:_ Eio.Process.mgr ->
  file:string ->
  line:int ->
  col:int ->
  expression:string ->
  (string, string) result
(** The type of [expression] in the scope of the position. *)

type error = { range : range option; kind : string; message : string }
(** [kind] is Merlin's error type: [typer], [parser], [warning], [config]... *)

val errors :
  fs:_ Eio.Path.t ->
  process_mgr:_ Eio.Process.mgr ->
  file:string ->
  (error list, string) result
(** Errors and warnings of the file. *)

type outline_item = {
  name : string;
  kind : string;
  typ : string option;
  range : range;
  children : outline_item list;
}

val outline :
  fs:_ Eio.Path.t ->
  process_mgr:_ Eio.Process.mgr ->
  file:string ->
  (outline_item list, string) result
(** The items defined in the file, in source order. *)

type occurrence = { file : string; range : range; stale : bool }
(** [stale] occurrences come from an index older than their file. *)

val occurrences :
  fs:_ Eio.Path.t ->
  process_mgr:_ Eio.Process.mgr ->
  scope:[ `Buffer | `Project | `Renaming ] ->
  file:string ->
  line:int ->
  col:int ->
  (occurrence list, string) result
(** Occurrences of the identifier at the position. [`Project] and [`Renaming]
    read the project index ([dune build @ocaml-index]); [`Renaming] also
    includes the related definitions, as needed to rename. *)

type search_result = { name : string; typ : string; where : location option }

val search_by_type :
  fs:_ Eio.Path.t ->
  process_mgr:_ Eio.Process.mgr ->
  file:string ->
  line:int ->
  col:int ->
  query:string ->
  limit:int ->
  (search_result list, string) result
(** Values whose type matches [query] (e.g. ["string -> int option"]), in the
    scope of the position. *)

type edit = { range : range; text : string }
(** Replace [range] of the queried file with [text]. *)

val case_analysis :
  fs:_ Eio.Path.t ->
  process_mgr:_ Eio.Process.mgr ->
  file:string ->
  start:position ->
  stop:position ->
  (edit, string) result
(** The case analysis (destruct) of the expression or pattern between [start]
    and [stop]: a match on an expression, the missing cases of a match, or the
    cases of a wildcard pattern. *)

val construct :
  fs:_ Eio.Path.t ->
  process_mgr:_ Eio.Process.mgr ->
  ?depth:int ->
  file:string ->
  line:int ->
  col:int ->
  unit ->
  (range * string list, string) result
(** Candidate expressions to fill the typed hole ([_]) at the position, and the
    hole's range. *)

val refactor_open :
  fs:_ Eio.Path.t ->
  process_mgr:_ Eio.Process.mgr ->
  action:[ `Qualify | `Unqualify ] ->
  file:string ->
  line:int ->
  col:int ->
  (edit list, string) result
(** The edits that qualify (or unqualify) the uses of the module opened at the
    position. *)
