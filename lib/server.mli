(** The atchoum MCP server: Merlin queries declared as mcp-kit tools.

    This is the only module that depends on mcp-kit. *)

[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

val type_enclosing :
  fs:_ Eio.Path.t -> process_mgr:_ Eio.Process.mgr -> Mcp_kit.Tool.t
(** The [type_enclosing] tool, with arguments [file], [line] (from 1) and [col]
    (from 0). It returns Merlin's raw JSON answer as text, or an error result
    when Merlin fails. See {!Merlin.type_enclosing}. *)

val locate : fs:_ Eio.Path.t -> process_mgr:_ Eio.Process.mgr -> Mcp_kit.Tool.t
(** The [locate] tool, with arguments [file], [line] (from 1) and [col] (from
    0), and optionally [prefix] and [look_for] (["interface"] or
    ["implementation"]). It returns Merlin's raw JSON answer as text, or an
    error result when Merlin fails. See {!Merlin.locate}. *)

val create :
  fs:_ Eio.Path.t -> process_mgr:_ Eio.Process.mgr -> unit -> Mcp_kit.Server.t
(** [create ~fs ~process_mgr ()] is the server with every atchoum tool. *)
