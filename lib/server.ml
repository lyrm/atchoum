[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

module Tool = Mcp_kit.Tool
module Schema = Mcp_kit.Schema

let ( let* ) = Result.bind

(* Sent to the client at initialization; Claude Code adds it to the system
   prompt while the server is connected. Keep it short. *)
let instructions =
  {|Merlin-backed tools for OCaml code (.ml and .mli files). Merlin type-checks the code, so its answers are exact where text search and reading only guess. When working on OCaml code, prefer them to grep, sed or reading whole files:
- understand: type_enclosing (type; expand=true for a module's signature), locate (definition), locate_type (definition of a value's type), document (doc comment), occurrences (uses, project-wide), outline (what a file defines), type_expression (type of any expression), search_by_type (find a function by its type);
- modify: errors (check a file after each change), rename (all uses, project-wide), case_analysis (generate match cases), construct (fill a typed hole _), qualify_open (remove or expand an open).

Target code with file and line plus either identifier (the name as written on that line) or col (from 0); lines start at 1.

rename, case_analysis and qualify_open write the files themselves (apply=false only shows the edits): read a file again before editing it yourself. Project-wide answers need the build artefacts: run `dune build` (and `dune build @ocaml-index` for occurrences and rename) when Merlin reports unbound modules or misses uses.|}

(* Arguments. *)

let file_prop =
  ( "file",
    Schema.string
      ~description:
        "Path to the OCaml source file. An absolute path is recommended."
      () )

let line_prop =
  ( "line",
    Schema.integer ~description:"Line number, starting at 1." ~minimum:1. () )

let target_props =
  [
    file_prop;
    line_prop;
    ( "identifier",
      Schema.string
        ~description:
          "The identifier to target on LINE, as written there (e.g. \
           wrap_printing_env or Printtyp.wrap_printing_env). Used to find the \
           column when col is not given."
        () );
    ( "col",
      Schema.integer
        ~description:"Column, starting at 0. Not needed with identifier."
        ~minimum:0. () );
  ]

let target_required = [ "file"; "line" ]

let apply_prop =
  ( "apply",
    Schema.bool
      ~description:
        "Write the edits to the files (default true); false only shows them."
      () )

(* Source text. *)

let load ~fs file =
  try Ok (Eio.Path.load Eio.Path.(fs / file))
  with Eio.Io _ as e -> Error (Printexc.to_string e)

let nth_line text n = List.nth_opt (String.split_on_char '\n' text) (n - 1)

let source_line ~fs file n =
  Result.to_option (load ~fs file)
  |> Fun.flip Option.bind (fun t -> nth_line t n)

let is_ident_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '\'' -> true
  | _ -> false

(* Column of the first occurrence of [ident] in [text] as a whole word; for a
   qualified [ident] (M.x), the column of its last component. *)
let find_identifier text ident =
  let n = String.length ident and m = String.length text in
  let last =
    match String.rindex_opt ident '.' with
    | Some i when i + 1 < n -> i + 1
    | _ -> 0
  in
  let word_at i =
    String.sub text i n = ident
    && (i = 0 || not (is_ident_char text.[i - 1]))
    && (i + n = m || not (is_ident_char text.[i + n]))
  in
  let rec go i =
    if n = 0 || i + n > m then None
    else if word_at i then Some (i + last)
    else go (i + 1)
  in
  go 0

(* [file], [line] and the column given by [col] or found from [identifier]. *)
let read_target ~fs args =
  let* file = Tool.Arg.string "file" args in
  let* line = Tool.Arg.int "line" args in
  let* col = Tool.Arg.(optional int) "col" args in
  let* identifier = Tool.Arg.(optional string) "identifier" args in
  let* col =
    match (col, identifier) with
    | Some col, _ -> Ok col
    | None, Some ident -> (
        let* text = load ~fs file in
        match nth_line text line with
        | None -> Error (Printf.sprintf "%s has no line %d" file line)
        | Some src -> (
            match find_identifier src ident with
            | Some col -> Ok col
            | None ->
                Error
                  (Printf.sprintf "%s not found on line %d: %s" ident line
                     (String.trim src))))
    | None, None -> Error "give identifier or col"
  in
  Ok (file, line, col)

let read_apply args =
  Result.map
    (Option.value ~default:true)
    (Tool.Arg.(optional bool) "apply" args)

(* Formatting. *)

let pos { Merlin.line; col } = Printf.sprintf "%d:%d" line col
let range { Merlin.start; stop } = pos start ^ "-" ^ pos stop

(* FILE:LINE:COL, then the source line, so that it needs no separate read. *)
let location_text ~fs { Merlin.file; pos = p } =
  let where = Printf.sprintf "%s:%s" file (pos p) in
  match Option.map String.trim (source_line ~fs file p.line) with
  | Some src when src <> "" -> where ^ "\n" ^ src
  | _ -> where

let indent prefix text =
  String.split_on_char '\n' text |> String.concat ("\n" ^ prefix)

(* Tools: a handler computes the answer text, or an error shown to Claude. *)

let tool ~title ~description ?(properties = target_props)
    ?(required = target_required) name handler =
  Tool.make ~title ~description
    ~input_schema:(Schema.object_ ~properties ~required ()) name (fun args ->
      match handler args with
      | Ok text -> Ok (Tool.text text)
      | Error msg -> Ok (Tool.error_text msg))

(* Understanding code. *)

let type_enclosing ~fs ~process_mgr =
  tool "type_enclosing" ~title:"Type enclosing"
    ~description:
      "Type of the innermost expression at a position, as reported by Merlin. \
       Use it instead of reading the surrounding code to work out a type. With \
       expand=true on a module name, its signature. Returns the type only."
    ~properties:
      (target_props
      @ [
          ( "expand",
            Schema.bool
              ~description:
                "Expand module types and abbreviations one level (a module's \
                 signature)."
              () );
        ])
    (fun args ->
      let* file, line, col = read_target ~fs args in
      let* expand = Tool.Arg.(optional bool) "expand" args in
      Merlin.type_enclosing ~fs ~process_mgr ?expand ~file ~line ~col ())

let look_for_of_string = function
  | None -> Ok None
  | Some "interface" -> Ok (Some `Interface)
  | Some "implementation" -> Ok (Some `Implementation)
  | Some other -> Error ("invalid look_for: " ^ other)

let locate ~fs ~process_mgr =
  tool "locate" ~title:"Locate definition"
    ~description:
      "Find where an identifier is defined, as reported by Merlin. Use it \
       instead of grep to find a definition, including in libraries and the \
       standard library. Returns FILE:LINE:COL followed by the definition's \
       source line."
    ~properties:
      (target_props
      @ [
          ( "prefix",
            Schema.string
              ~description:
                "Identifier to locate instead of the targeted one, possibly \
                 qualified (e.g. List.map); the target still sets the scope."
              () );
          ( "look_for",
            Schema.enum
              ~description:
                "Prefer the interface (.mli) or the implementation (.ml)."
              [ `String "interface"; `String "implementation" ] );
        ])
    (fun args ->
      let* file, line, col = read_target ~fs args in
      let* prefix = Tool.Arg.(optional string) "prefix" args in
      let* look_for = Tool.Arg.(optional string) "look_for" args in
      let* look_for = look_for_of_string look_for in
      let* loc =
        Merlin.locate ~fs ~process_mgr ?prefix ?look_for ~file ~line ~col ()
      in
      Ok (location_text ~fs loc))

let locate_type ~fs ~process_mgr =
  tool "locate_type" ~title:"Locate type"
    ~description:
      "Find where the type of the value at a position is defined. Returns \
       FILE:LINE:COL followed by the source line." (fun args ->
      let* file, line, col = read_target ~fs args in
      let* loc = Merlin.locate_type ~fs ~process_mgr ~file ~line ~col in
      Ok (location_text ~fs loc))

let document ~fs ~process_mgr =
  tool "document" ~title:"Documentation"
    ~description:
      "The documentation comment of an identifier, wherever it is defined. Use \
       it instead of reading .mli files." (fun args ->
      let* file, line, col = read_target ~fs args in
      Merlin.document ~fs ~process_mgr ~file ~line ~col)

let type_expression ~fs ~process_mgr =
  tool "type_expression" ~title:"Type of an expression"
    ~description:
      "Type of any OCaml expression (e.g. `List.map f`) in the scope of a line \
       of a file, without it being in the file."
    ~properties:
      [
        file_prop;
        line_prop;
        ("expression", Schema.string ~description:"The expression to type." ());
      ]
    ~required:[ "file"; "line"; "expression" ]
    (fun args ->
      let* file = Tool.Arg.string "file" args in
      let* line = Tool.Arg.int "line" args in
      let* expression = Tool.Arg.string "expression" args in
      Merlin.type_expression ~fs ~process_mgr ~file ~line ~col:0 ~expression)

let occurrences_text ~fs (occs : Merlin.occurrence list) =
  let files =
    List.fold_left
      (fun acc (o : Merlin.occurrence) ->
        if List.mem o.file acc then acc else o.file :: acc)
      [] occs
    |> List.rev
  in
  let per_file file =
    let text = Result.to_option (load ~fs file) in
    let lines =
      List.filter_map
        (fun (o : Merlin.occurrence) ->
          if o.file <> file then None
          else
            let src =
              Option.bind text (fun t -> nth_line t o.range.start.line)
              |> Option.fold ~none:"" ~some:String.trim
            in
            Some
              (Printf.sprintf "  %s%s: %s" (pos o.range.start)
                 (if o.stale then " (stale)" else "")
                 src))
        occs
    in
    String.concat "\n" (file :: lines)
  in
  Printf.sprintf "%d occurrences in %d files:\n%s" (List.length occs)
    (List.length files)
    (String.concat "\n" (List.map per_file files))

let occurrences ~fs ~process_mgr =
  tool "occurrences" ~title:"Occurrences"
    ~description:
      "All the uses of an identifier, resolved by Merlin (no homonyms, through \
       opens and aliases). Use it instead of grep to find who uses a function \
       or type. Project scope reads the index built by `dune build \
       @ocaml-index`. Returns the occurrences grouped by file, with their \
       source lines."
    ~properties:
      (target_props
      @ [
          ( "scope",
            Schema.enum ~description:"file or project (default project)."
              [ `String "file"; `String "project" ] );
        ])
    (fun args ->
      let* file, line, col = read_target ~fs args in
      let* scope = Tool.Arg.(optional string) "scope" args in
      let scope = if scope = Some "file" then `Buffer else `Project in
      let* occs = Merlin.occurrences ~fs ~process_mgr ~scope ~file ~line ~col in
      Ok (occurrences_text ~fs occs))

let rec outline_lines depth (items : Merlin.outline_item list) =
  List.concat_map
    (fun (i : Merlin.outline_item) ->
      Printf.sprintf "%s%d-%d %s %s%s"
        (String.make (2 * depth) ' ')
        i.range.start.line i.range.stop.line
        (String.lowercase_ascii i.kind)
        i.name
        (match i.typ with
        | Some ty -> " : " ^ indent (String.make ((2 * depth) + 4) ' ') ty
        | None -> "")
      :: outline_lines (depth + 1) i.children)
    items

let outline ~fs ~process_mgr =
  tool "outline" ~title:"Outline"
    ~description:
      "What a file defines: values (with their types), types, modules, \
       classes, nested, with their line ranges. Use it instead of reading a \
       whole file to find your way in it."
    ~properties:[ file_prop ] ~required:[ "file" ] (fun args ->
      let* file = Tool.Arg.string "file" args in
      let* items = Merlin.outline ~fs ~process_mgr ~file in
      match outline_lines 0 items with
      | [] -> Ok "Nothing defined."
      | lines -> Ok (String.concat "\n" lines))

let search_by_type ~fs ~process_mgr =
  tool "search_by_type" ~title:"Search by type"
    ~description:
      "Find values by their type (e.g. `string -> int option`, `'a list -> \
       int`) among those in scope at a line of a file: the project, its \
       libraries and the standard library. Use it before writing a helper that \
       may already exist."
    ~properties:
      [
        file_prop;
        ("query", Schema.string ~description:"The type to look for." ());
        ( "line",
          Schema.integer
            ~description:"Line whose scope is searched (default 1)." ~minimum:1.
            () );
        ( "limit",
          Schema.integer ~description:"Maximum results (default 10)."
            ~minimum:1. () );
      ]
    ~required:[ "file"; "query" ]
    (fun args ->
      let* file = Tool.Arg.string "file" args in
      let* query = Tool.Arg.string "query" args in
      let* line = Tool.Arg.(optional int) "line" args in
      let* limit = Tool.Arg.(optional int) "limit" args in
      let* results =
        Merlin.search_by_type ~fs ~process_mgr ~file
          ~line:(Option.value ~default:1 line)
          ~col:0 ~query
          ~limit:(Option.value ~default:10 limit)
      in
      match results with
      | [] -> Ok "No match."
      | results ->
          Ok
            (String.concat "\n"
               (List.map
                  (fun (r : Merlin.search_result) ->
                    Printf.sprintf "%s : %s%s" r.name r.typ
                      (match r.where with
                      | Some { file; pos = p } ->
                          Printf.sprintf "  (%s:%d)" (Filename.basename file)
                            p.line
                      | None -> ""))
                  results)))

(* Modifying code. *)

let errors ~fs ~process_mgr =
  tool "errors" ~title:"Errors"
    ~description:
      "Type errors, syntax errors and warnings of a file, from Merlin, in \
       about a second. Use it after each change instead of running the build."
    ~properties:[ file_prop ] ~required:[ "file" ] (fun args ->
      let* file = Tool.Arg.string "file" args in
      let* errs = Merlin.errors ~fs ~process_mgr ~file in
      match errs with
      | [] -> Ok "No errors."
      | errs ->
          Ok
            (String.concat "\n"
               (List.map
                  (fun (e : Merlin.error) ->
                    Printf.sprintf "%s%s: %s"
                      (match e.range with
                      | Some r -> range r ^ " "
                      | None -> "")
                      e.kind (indent "  " e.message))
                  errs)))

(* Apply [edits] unless [apply] is false; [summary] describes them. *)
let apply_edits ~fs ~apply edits summary =
  if not apply then Ok (summary ^ "\n(not applied)")
  else
    let* files = Edit.apply ~fs edits in
    Ok (Printf.sprintf "%s\nWritten: %s" summary (String.concat ", " files))

let rename ~fs ~process_mgr =
  tool "rename" ~title:"Rename"
    ~description:
      "Rename an identifier and all its uses, project-wide, as resolved by \
       Merlin (uses through opens, aliases and qualified paths; no homonyms). \
       Needs the index built by `dune build @ocaml-index` for other files. \
       Writes the files unless apply=false."
    ~properties:
      (target_props
      @ [
          ("new_name", Schema.string ~description:"The new name." ());
          apply_prop;
        ])
    ~required:(target_required @ [ "new_name" ])
    (fun args ->
      let* file, line, col = read_target ~fs args in
      let* new_name = Tool.Arg.string "new_name" args in
      let* apply = read_apply args in
      let* occs =
        Merlin.occurrences ~fs ~process_mgr ~scope:`Renaming ~file ~line ~col
      in
      if occs = [] then Error "no occurrence found"
      else if List.exists (fun (o : Merlin.occurrence) -> o.stale) occs then
        Error
          "the project index is older than some files: run `dune build \
           @ocaml-index` first"
      else
        (* An occurrence may cover a qualified path: keep its qualifier. *)
        let* edits =
          List.fold_left
            (fun acc (o : Merlin.occurrence) ->
              let* acc = acc in
              let* text = load ~fs o.file in
              let* old = Edit.slice text o.range in
              let qualifier =
                match String.rindex_opt old '.' with
                | Some i -> String.sub old 0 (i + 1)
                | None -> ""
              in
              Ok
                ({
                   Edit.file = o.file;
                   edit = { range = o.range; text = qualifier ^ new_name };
                 }
                :: acc))
            (Ok []) occs
        in
        apply_edits ~fs ~apply (List.rev edits) (occurrences_text ~fs occs))

let case_analysis ~fs ~process_mgr =
  tool "case_analysis" ~title:"Case analysis"
    ~description:
      "Generate pattern-matching cases with Merlin's destruct: on an \
       expression, a match over its type; on a match, its missing cases; on a \
       wildcard pattern, its cases. Target the expression or pattern (end_line \
       and end_col extend the target to a range). Writes the file unless \
       apply=false."
    ~properties:
      (target_props
      @ [
          ( "end_line",
            Schema.integer ~description:"End line of the target range."
              ~minimum:1. () );
          ( "end_col",
            Schema.integer ~description:"End column of the target range."
              ~minimum:0. () );
          apply_prop;
        ])
    (fun args ->
      let* file, line, col = read_target ~fs args in
      let* end_line = Tool.Arg.(optional int) "end_line" args in
      let* end_col = Tool.Arg.(optional int) "end_col" args in
      let* apply = read_apply args in
      let start = { Merlin.line; col } in
      let stop =
        {
          Merlin.line = Option.value ~default:line end_line;
          col = Option.value ~default:col end_col;
        }
      in
      let* edit = Merlin.case_analysis ~fs ~process_mgr ~file ~start ~stop in
      apply_edits ~fs ~apply
        [ { Edit.file; edit } ]
        (Printf.sprintf "%s:%s replaced by:\n%s" file (range edit.range)
           edit.text))

let construct ~fs ~process_mgr =
  tool "construct" ~title:"Construct"
    ~description:
      "Candidate expressions, from Merlin, to fill a typed hole `_` with a \
       value of its type. Target the hole. Returns the hole's range and the \
       candidates; replace the hole yourself."
    ~properties:
      (target_props
      @ [
          ( "depth",
            Schema.integer
              ~description:"Search depth (default 1; higher fills sub-holes)."
              ~minimum:1. () );
        ])
    (fun args ->
      let* file, line, col = read_target ~fs args in
      let* depth = Tool.Arg.(optional int) "depth" args in
      let* r, candidates =
        Merlin.construct ~fs ~process_mgr ?depth ~file ~line ~col ()
      in
      match candidates with
      | [] -> Error "no candidate"
      | cs ->
          Ok (Printf.sprintf "hole %s:\n%s" (range r) (String.concat "\n" cs)))

let qualify_open ~fs ~process_mgr =
  tool "qualify_open" ~title:"Qualify open"
    ~description:
      "Qualify (or unqualify) every use of the module opened by an `open`: \
       target the module name in the open. Use it to remove an open without \
       breaking the code. Writes the file unless apply=false."
    ~properties:
      (target_props
      @ [
          ( "action",
            Schema.enum ~description:"qualify (default) or unqualify."
              [ `String "qualify"; `String "unqualify" ] );
          apply_prop;
        ])
    (fun args ->
      let* file, line, col = read_target ~fs args in
      let* action = Tool.Arg.(optional string) "action" args in
      let action = if action = Some "unqualify" then `Unqualify else `Qualify in
      let* apply = read_apply args in
      let* edits =
        Merlin.refactor_open ~fs ~process_mgr ~action ~file ~line ~col
      in
      if edits = [] then Error "nothing to change"
      else
        apply_edits ~fs ~apply
          (List.map (fun edit -> { Edit.file; edit }) edits)
          (String.concat "\n"
             (List.map
                (fun (e : Merlin.edit) ->
                  Printf.sprintf "%s -> %s" (range e.range) e.text)
                edits)))

let tools ~fs ~process_mgr =
  [
    type_enclosing ~fs ~process_mgr;
    locate ~fs ~process_mgr;
    locate_type ~fs ~process_mgr;
    document ~fs ~process_mgr;
    occurrences ~fs ~process_mgr;
    outline ~fs ~process_mgr;
    type_expression ~fs ~process_mgr;
    search_by_type ~fs ~process_mgr;
    errors ~fs ~process_mgr;
    rename ~fs ~process_mgr;
    case_analysis ~fs ~process_mgr;
    construct ~fs ~process_mgr;
    qualify_open ~fs ~process_mgr;
  ]

let create ~fs ~process_mgr () =
  let server =
    Mcp_kit.Server.create ~name:"atchoum" ~version:"0.2.0" ~instructions ()
  in
  match Mcp_kit.Server.add_tools server (tools ~fs ~process_mgr) with
  | Ok server -> server
  | Error _ -> failwith "atchoum: duplicate tool declaration"
