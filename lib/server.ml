[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

module Tool = Mcp_kit.Tool
module Schema = Mcp_kit.Schema

let ( let* ) = Result.bind

(* Sent to the client at initialization; Claude Code adds it to the system
   prompt while the server is connected. Keep it short. *)
let instructions =
  {|Merlin-backed tools for OCaml code (.ml and .mli files). Merlin type-checks the code, so its answers are exact where text search only guesses.

When working on OCaml code, use these tools instead of grep, sed or reading files:
- type of an expression or identifier: type_enclosing;
- where an identifier is defined, in the project or in a library: locate (look_for "interface" gives the .mli).

Every tool takes a file and a position: line starts at 1 and col at 0. Pass absolute paths.

Answers are short: a type, or a location with the source line of the definition. If Merlin reports an unbound module of the same project, run `dune build` first: Merlin reads the build artefacts of the other modules.|}

let type_enclosing_description =
  "Type of the innermost expression at LINE:COL in an OCaml file, as reported \
   by Merlin. Use it instead of reading the surrounding code to work out a \
   type. Lines start at 1, columns at 0. Returns the type only."

(* Every tool takes a position in a file. *)
let position_properties =
  [
    ( "file",
      Schema.string
        ~description:
          "Path to the OCaml source file. An absolute path is recommended."
        () );
    ( "line",
      Schema.integer ~description:"Line number, starting at 1." ~minimum:1. ()
    );
    ( "col",
      Schema.integer ~description:"Column number, starting at 0." ~minimum:0. ()
    );
  ]

let position_required = [ "file"; "line"; "col" ]

let read_position args =
  let* file = Tool.Arg.string "file" args in
  let* line = Tool.Arg.int "line" args in
  let* col = Tool.Arg.int "col" args in
  Ok (file, line, col)

let tool_result to_text = function
  | Ok answer -> Ok (Tool.text (to_text answer))
  | Error msg -> Ok (Tool.error_text msg)

(* Line [n] (from 1) of [file], trimmed, if it can be read. *)
let source_line ~fs file n =
  match Eio.Path.load Eio.Path.(fs / file) with
  | exception Eio.Io _ -> None
  | contents ->
      List.nth_opt (String.split_on_char '\n' contents) (n - 1)
      |> Option.map String.trim

(* FILE:LINE:COL, then the definition's source line so that it needs no
   separate read. *)
let location_text ~fs { Merlin.file; pos = { line; col } } =
  let where = Printf.sprintf "%s:%d:%d" file line col in
  match source_line ~fs file line with
  | Some src when src <> "" -> where ^ "\n" ^ src
  | _ -> where

let type_enclosing_schema =
  Schema.object_ ~properties:position_properties ~required:position_required ()

let type_enclosing ~fs ~process_mgr =
  Tool.make ~title:"Type enclosing" ~description:type_enclosing_description
    ~input_schema:type_enclosing_schema "type_enclosing" (fun args ->
      let* file, line, col = read_position args in
      tool_result Fun.id
        (Merlin.type_enclosing ~fs ~process_mgr ~file ~line ~col))

let locate_description =
  "Find where the identifier at LINE:COL (or PREFIX) in an OCaml file is \
   defined, as reported by Merlin. Use it instead of grep to find a \
   definition, including in libraries and the standard library. Lines start at \
   1, columns at 0. Returns FILE:LINE:COL of the definition followed by its \
   source line, or an error explaining why it could not be found."

let locate_schema =
  Schema.object_
    ~properties:
      (position_properties
      @ [
          ( "prefix",
            Schema.string
              ~description:
                "Identifier to locate instead of the one at LINE:COL, possibly \
                 qualified (e.g. List.map). LINE:COL still sets the scope."
              () );
          ( "look_for",
            Schema.enum
              ~description:
                "Prefer the interface (.mli) or the implementation (.ml)."
              [ `String "interface"; `String "implementation" ] );
        ])
    ~required:position_required ()

let look_for_of_string = function
  | None -> Ok None
  | Some "interface" -> Ok (Some `Interface)
  | Some "implementation" -> Ok (Some `Implementation)
  | Some other -> Error ("invalid look_for: " ^ other)

let locate ~fs ~process_mgr =
  Tool.make ~title:"Locate definition" ~description:locate_description
    ~input_schema:locate_schema "locate" (fun args ->
      let* file, line, col = read_position args in
      let* prefix = Tool.Arg.(optional string) "prefix" args in
      let* look_for = Tool.Arg.(optional string) "look_for" args in
      let* look_for = look_for_of_string look_for in
      tool_result (location_text ~fs)
        (Merlin.locate ~fs ~process_mgr ?prefix ?look_for ~file ~line ~col ()))

let create ~fs ~process_mgr () =
  let server =
    Mcp_kit.Server.create ~name:"atchoum" ~version:"0.1.0" ~instructions ()
  in
  match
    Mcp_kit.Server.add_tools server
      [ type_enclosing ~fs ~process_mgr; locate ~fs ~process_mgr ]
  with
  | Ok server -> server
  | Error _ -> failwith "atchoum: duplicate tool declaration"
