(** The atchoum MCP server: Merlin queries declared as mcp-kit tools.

    This is the only module that depends on mcp-kit. Every tool targets code
    with [file] and [line] plus [identifier] (found on that line) or [col], and
    answers with short text; failures are error results. *)

[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

val find_identifier : string -> string -> int option
(** [find_identifier line ident] is the column of the first whole-word
    occurrence of [ident] in [line]; for a qualified [ident] ([M.x]), the column
    of its last component. *)

val tools :
  fs:_ Eio.Path.t -> process_mgr:_ Eio.Process.mgr -> Mcp_kit.Tool.t list
(** Every tool, in the order of {!create}'s listing: [type_enclosing], [locate],
    [locate_type], [document], [occurrences], [outline], [type_expression],
    [search_by_type], [errors], [rename], [case_analysis], [construct],
    [qualify_open]. *)

val create :
  fs:_ Eio.Path.t -> process_mgr:_ Eio.Process.mgr -> unit -> Mcp_kit.Server.t
(** [create ~fs ~process_mgr ()] is the server with every atchoum tool. *)
