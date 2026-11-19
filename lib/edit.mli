(** Applying Merlin's edits to source files. *)

[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type t = { file : string; edit : Merlin.edit }

val slice : string -> Merlin.range -> (string, string) result
(** [slice text range] is the part of [text] in [range]. *)

val apply_to_text : string -> Merlin.edit list -> (string, string) result
(** [apply_to_text text edits] replaces each edit's range (byte-based columns)
    with its text. [Error] when a position is out of [text] or edits overlap. *)

val apply : fs:_ Eio.Path.t -> t list -> (string list, string) result
(** [apply ~fs edits] applies [edits] to their files and returns the files
    written, in order of first appearance. No file is written unless every
    file's edits apply. *)
