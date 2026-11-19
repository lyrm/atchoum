[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

let contains ~sub s =
  let n = String.length sub and m = String.length s in
  let rec go i = i + n <= m && (String.sub s i n = sub || go (i + 1)) in
  go 0

let check_contains ~sub text =
  if not (contains ~sub text) then Alcotest.failf "expected %S in:\n%s" sub text

(* Standalone files outside the repository, so that Merlin does not ask dune
   for a configuration. *)
let with_file contents f =
  let dir = Filename.temp_dir "atchoum" "" in
  let file = Filename.concat dir "sample.ml" in
  Out_channel.with_open_text file (fun oc -> output_string oc contents);
  Fun.protect
    ~finally:(fun () ->
      Sys.remove file;
      Sys.rmdir dir)
    (fun () -> f file)

let read file = In_channel.with_open_text file In_channel.input_all

(* At 1:4 is [x], of type [int]; at 2:8 is a use of [x]; at 3:13 is
   [List.map]. *)
let sample = "let x = 1 + 2\nlet y = x\nlet z = List.map\n"

let shapes =
  String.concat "\n"
    [
      "type t = Circle of float | Square of float";
      "(** [area s] is the area of [s]. *)";
      "let area = function Circle r -> r *. r | Square c -> c *. c";
      "let name s = match s with Circle _ -> \"circle\"";
      "let total l = List.fold_left (fun acc s -> acc +. area s) 0. l";
      "let make () : t = _";
      "module M = struct let v = 1 end";
      "open M";
      "let w = v + 1";
      "";
    ]

let get_ok = function
  | Ok v -> v
  | Error err -> Alcotest.failf "unexpected error: %s" err

(* Merlin. *)

let merlin_type_enclosing ~fs ~process_mgr () =
  with_file sample @@ fun file ->
  Atchoum.Merlin.type_enclosing ~fs ~process_mgr ~file ~line:1 ~col:4 ()
  |> get_ok
  |> Alcotest.(check string) "the type only" "int"

let merlin_missing_file ~fs ~process_mgr () =
  match
    Atchoum.Merlin.type_enclosing ~fs ~process_mgr
      ~file:"/nonexistent/atchoum/sample.ml" ~line:1 ~col:0 ()
  with
  | Ok ty -> Alcotest.failf "unexpected answer: %s" ty
  | Error _ -> ()

let merlin_locate ~fs ~process_mgr () =
  with_file sample @@ fun file ->
  let (loc : Atchoum.Merlin.location) =
    Atchoum.Merlin.locate ~fs ~process_mgr ~file ~line:2 ~col:8 () |> get_ok
  in
  Alcotest.(check string) "same file" file loc.file;
  Alcotest.(check (pair int int))
    "x is defined at 1:4" (1, 4)
    (loc.pos.line, loc.pos.col)

let merlin_locate_prefix ~fs ~process_mgr () =
  with_file sample @@ fun file ->
  let (loc : Atchoum.Merlin.location) =
    Atchoum.Merlin.locate ~fs ~process_mgr ~prefix:"List.iter"
      ~look_for:`Interface ~file ~line:2 ~col:0 ()
    |> get_ok
  in
  Alcotest.(check string)
    "List.iter is declared in list.mli" "list.mli"
    (Filename.basename loc.file)

let merlin_locate_not_found ~fs ~process_mgr () =
  with_file sample @@ fun file ->
  match
    Atchoum.Merlin.locate ~fs ~process_mgr ~prefix:"nope" ~file ~line:2 ~col:0
      ()
  with
  | Ok (loc : Atchoum.Merlin.location) ->
      Alcotest.failf "unexpected location: %s" loc.file
  | Error reason -> check_contains ~sub:"Not in environment" reason

(* Pure helpers. *)

let find_identifier () =
  let check msg line ident expected =
    Alcotest.(check (option int))
      msg expected
      (Atchoum.Server.find_identifier line ident)
  in
  check "qualified use" "let both = List.map" "List.map" (Some 16);
  check "last component" "  Printtyp.wrap_printing_env env" "wrap_printing_env"
    (Some 11);
  check "whole word" "let xs = x" "x" (Some 9);
  check "absent" "let y = z" "x" None

let apply_to_text () =
  let r l1 c1 l2 c2 =
    {
      Atchoum.Merlin.start = { line = l1; col = c1 };
      stop = { line = l2; col = c2 };
    }
  in
  let edits =
    [
      { Atchoum.Merlin.range = r 1 4 1 5; text = "abc" };
      { range = r 2 8 2 9; text = "abc" };
    ]
  in
  Atchoum.Edit.apply_to_text "let x = 1\nlet y = x\n" edits
  |> get_ok
  |> Alcotest.(check string) "both edits" "let abc = 1\nlet y = abc\n";
  match
    Atchoum.Edit.apply_to_text "let x = 1\n"
      [ { range = r 1 0 1 5; text = "" }; { range = r 1 4 1 9; text = "" } ]
  with
  | Ok _ -> Alcotest.fail "overlapping edits accepted"
  | Error _ -> ()

(* Tools, through mcp-kit's argument validation. *)

let call ~fs ~process_mgr name args =
  let tool =
    List.find
      (fun t -> Mcp_kit.Tool.name t = name)
      (Atchoum.Server.tools ~fs ~process_mgr)
  in
  Mcp_kit.Tool.call tool (`Assoc args)

let text_of (result : Mcp_kit.Tool.result) =
  String.concat ""
    (List.filter_map
       (function Mcp_kit.Tool.Text s -> Some s | _ -> None)
       result.content)

let ok_text result =
  if result.Mcp_kit.Tool.is_error then
    Alcotest.failf "error result: %s" (text_of result);
  text_of result

let target ?(extra = []) file line ident =
  [ ("file", `String file); ("line", `Int line); ("identifier", `String ident) ]
  @ extra

let tool_type_enclosing ~fs ~process_mgr () =
  with_file sample @@ fun file ->
  call ~fs ~process_mgr "type_enclosing"
    [ ("file", `String file); ("line", `Int 1); ("col", `Int 4) ]
  |> ok_text
  |> Alcotest.(check string) "col" "int";
  with_file shapes @@ fun file ->
  call ~fs ~process_mgr "type_enclosing" (target file 5 "area")
  |> ok_text
  |> Alcotest.(check string) "identifier" "t -> float"

let tool_invalid_line ~fs ~process_mgr () =
  with_file sample @@ fun file ->
  let result =
    call ~fs ~process_mgr "type_enclosing"
      [ ("file", `String file); ("line", `Int 0); ("col", `Int 4) ]
  in
  Alcotest.(check bool) "line 0 is rejected" true result.is_error

let tool_missing_identifier ~fs ~process_mgr () =
  with_file shapes @@ fun file ->
  let result = call ~fs ~process_mgr "type_enclosing" (target file 5 "nope") in
  Alcotest.(check bool) "error" true result.is_error;
  check_contains ~sub:"nope not found on line 5" (text_of result)

let tool_locate ~fs ~process_mgr () =
  with_file sample @@ fun file ->
  let text =
    call ~fs ~process_mgr "locate"
      (target file 3 "List.map" ~extra:[ ("look_for", `String "interface") ])
    |> ok_text
  in
  check_contains ~sub:"list.mli:" text;
  check_contains ~sub:"\nval map :" text

let tool_locate_not_found ~fs ~process_mgr () =
  with_file sample @@ fun file ->
  let result =
    call ~fs ~process_mgr "locate"
      [
        ("file", `String file);
        ("line", `Int 2);
        ("col", `Int 0);
        ("prefix", `String "nope");
      ]
  in
  Alcotest.(check bool) "not found is an error" true result.is_error

let tool_invalid_look_for ~fs ~process_mgr () =
  with_file sample @@ fun file ->
  let result =
    call ~fs ~process_mgr "locate"
      (target file 3 "List.map" ~extra:[ ("look_for", `String "foo") ])
  in
  Alcotest.(check bool) "look_for foo is rejected" true result.is_error

let tool_locate_type ~fs ~process_mgr () =
  with_file shapes @@ fun file ->
  call ~fs ~process_mgr "locate_type" (target file 4 "s")
  |> ok_text
  |> check_contains ~sub:":1:5\ntype t ="

let tool_document ~fs ~process_mgr () =
  with_file shapes @@ fun file ->
  call ~fs ~process_mgr "document" (target file 5 "area")
  |> ok_text
  |> Alcotest.(check string) "doc comment" "[area s] is the area of [s]."

let tool_type_expression ~fs ~process_mgr () =
  with_file shapes @@ fun file ->
  call ~fs ~process_mgr "type_expression"
    [
      ("file", `String file);
      ("line", `Int 6);
      ("expression", `String "List.map area");
    ]
  |> ok_text
  |> Alcotest.(check string) "type" "t list -> float list"

let tool_outline ~fs ~process_mgr () =
  with_file shapes @@ fun file ->
  let text =
    call ~fs ~process_mgr "outline" [ ("file", `String file) ] |> ok_text
  in
  check_contains ~sub:"3-3 value area : t -> float" text;
  check_contains ~sub:"7-7 module M" text;
  check_contains ~sub:"\n  7-7 value v : int" text

let tool_occurrences ~fs ~process_mgr () =
  with_file shapes @@ fun file ->
  let text =
    call ~fs ~process_mgr "occurrences"
      (target file 5 "area" ~extra:[ ("scope", `String "file") ])
    |> ok_text
  in
  check_contains ~sub:"2 occurrences in 1 files:" text;
  check_contains ~sub:"  3:4: let area" text;
  check_contains ~sub:"  5:50: let total" text

let tool_search_by_type ~fs ~process_mgr () =
  with_file shapes @@ fun file ->
  call ~fs ~process_mgr "search_by_type"
    [
      ("file", `String file); ("query", `String "t -> float"); ("line", `Int 9);
    ]
  |> ok_text
  |> check_contains ~sub:"area : t -> float"

let tool_errors ~fs ~process_mgr () =
  ( with_file sample @@ fun file ->
    call ~fs ~process_mgr "errors" [ ("file", `String file) ]
    |> ok_text
    |> Alcotest.(check string) "clean file" "No errors." );
  with_file "let x = 1 + \"a\"\n" @@ fun file ->
  call ~fs ~process_mgr "errors" [ ("file", `String file) ]
  |> ok_text
  |> check_contains ~sub:"1:12-1:15 typer: This constant has type string"

let tool_rename ~fs ~process_mgr () =
  with_file shapes @@ fun file ->
  let text =
    call ~fs ~process_mgr "rename"
      (target file 5 "area" ~extra:[ ("new_name", `String "surface") ])
    |> ok_text
  in
  check_contains ~sub:"Written: " text;
  let source = read file in
  check_contains ~sub:"let surface = function" source;
  check_contains ~sub:"acc +. surface s" source;
  Alcotest.(check bool) "no area left" false (contains ~sub:"area s)" source)

let tool_rename_dry_run ~fs ~process_mgr () =
  with_file shapes @@ fun file ->
  let text =
    call ~fs ~process_mgr "rename"
      (target file 5 "area"
         ~extra:[ ("new_name", `String "surface"); ("apply", `Bool false) ])
    |> ok_text
  in
  check_contains ~sub:"(not applied)" text;
  Alcotest.(check string) "file unchanged" shapes (read file)

let tool_case_analysis ~fs ~process_mgr () =
  with_file shapes @@ fun file ->
  call ~fs ~process_mgr "case_analysis" (target file 4 "Circle")
  |> ok_text
  |> check_contains ~sub:"Square _";
  check_contains ~sub:"| Square _ -> _" (read file)

let tool_construct ~fs ~process_mgr () =
  with_file shapes @@ fun file ->
  let text = call ~fs ~process_mgr "construct" (target file 6 "_") |> ok_text in
  check_contains ~sub:"hole 6:18-6:19:" text;
  check_contains ~sub:"(Circle _)" text

let tool_qualify_open ~fs ~process_mgr () =
  with_file shapes @@ fun file ->
  call ~fs ~process_mgr "qualify_open" (target file 8 "M") |> ok_text |> ignore;
  check_contains ~sub:"let w = M.v + 1" (read file)

let () =
  Eio_main.run @@ fun env ->
  let fs = Eio.Stdenv.fs env and process_mgr = Eio.Stdenv.process_mgr env in
  let case name f = Alcotest.test_case name `Quick (f ~fs ~process_mgr) in
  Alcotest.run ~and_exit:false "atchoum"
    [
      ( "merlin",
        [
          case "type_enclosing" merlin_type_enclosing;
          case "missing file" merlin_missing_file;
          case "locate" merlin_locate;
          case "locate with prefix" merlin_locate_prefix;
          case "locate not found" merlin_locate_not_found;
        ] );
      ( "helpers",
        [
          Alcotest.test_case "find_identifier" `Quick find_identifier;
          Alcotest.test_case "apply_to_text" `Quick apply_to_text;
        ] );
      ( "tools",
        [
          case "type_enclosing" tool_type_enclosing;
          case "invalid line" tool_invalid_line;
          case "missing identifier" tool_missing_identifier;
          case "locate" tool_locate;
          case "locate not found" tool_locate_not_found;
          case "invalid look_for" tool_invalid_look_for;
          case "locate_type" tool_locate_type;
          case "document" tool_document;
          case "type_expression" tool_type_expression;
          case "outline" tool_outline;
          case "occurrences" tool_occurrences;
          case "search_by_type" tool_search_by_type;
          case "errors" tool_errors;
          case "rename" tool_rename;
          case "rename dry run" tool_rename_dry_run;
          case "case_analysis" tool_case_analysis;
          case "construct" tool_construct;
          case "qualify_open" tool_qualify_open;
        ] );
    ]
