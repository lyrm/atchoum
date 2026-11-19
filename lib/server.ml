[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

module Tool = Mcp_kit.Tool
module Schema = Mcp_kit.Schema

let ( let* ) = Result.bind

let type_enclosing_description =
  "Type of the expression at LINE:COL in an OCaml file, as reported by Merlin. \
   Lines start at 1, columns at 0. Returns Merlin's raw JSON answer: the \
   enclosing expressions, innermost first, with their positions and types."

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

let tool_result = function
  | Ok json -> Ok (Tool.text json)
  | Error msg -> Ok (Tool.error_text msg)

let type_enclosing_schema =
  Schema.object_ ~properties:position_properties ~required:position_required ()

let type_enclosing ~fs ~process_mgr =
  Tool.make ~title:"Type enclosing" ~description:type_enclosing_description
    ~input_schema:type_enclosing_schema "type_enclosing" (fun args ->
      let* file, line, col = read_position args in
      tool_result (Merlin.type_enclosing ~fs ~process_mgr ~file ~line ~col))

let locate_description =
  "Find where the identifier at LINE:COL (or PREFIX) in an OCaml file is \
   defined, as reported by Merlin. Lines start at 1, columns at 0. Returns \
   Merlin's raw JSON answer: the file and position of the definition, or a \
   string explaining why it could not be found."

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
      tool_result
        (Merlin.locate ~fs ~process_mgr ?prefix ?look_for ~file ~line ~col ()))

let create ~fs ~process_mgr () =
  let server = Mcp_kit.Server.create ~name:"atchoum" ~version:"0.1.0" () in
  match
    Mcp_kit.Server.add_tools server
      [ type_enclosing ~fs ~process_mgr; locate ~fs ~process_mgr ]
  with
  | Ok server -> server
  | Error _ -> failwith "atchoum: duplicate tool declaration"
