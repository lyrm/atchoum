[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

let contains ~sub s =
  let n = String.length sub and m = String.length s in
  let rec go i = i + n <= m && (String.sub s i n = sub || go (i + 1)) in
  go 0

(* A standalone file outside the repository, so that Merlin does not ask dune
   for a configuration. At 1:4 is [x], of type [int]; at 2:8 is a use of [x];
   at 3:13 is [List.map]. *)
let sample = "let x = 1 + 2\nlet y = x\nlet z = List.map\n"

let with_sample f =
  let dir = Filename.temp_dir "atchoum" "" in
  let file = Filename.concat dir "sample.ml" in
  Out_channel.with_open_text file (fun oc -> output_string oc sample);
  Fun.protect
    ~finally:(fun () ->
      Sys.remove file;
      Sys.rmdir dir)
    (fun () -> f file)

let check_ok ~sub ~msg = function
  | Ok json -> Alcotest.(check bool) msg true (contains ~sub json)
  | Error err -> Alcotest.failf "unexpected error: %s" err

let merlin_type_enclosing ~fs ~process_mgr () =
  with_sample @@ fun file ->
  Atchoum.Merlin.type_enclosing ~fs ~process_mgr ~file ~line:1 ~col:4
  |> check_ok ~sub:{|"type":"int"|} ~msg:"answer contains the type int"

let merlin_missing_file ~fs ~process_mgr () =
  match
    Atchoum.Merlin.type_enclosing ~fs ~process_mgr
      ~file:"/nonexistent/atchoum/sample.ml" ~line:1 ~col:0
  with
  | Ok json -> Alcotest.failf "unexpected answer: %s" json
  | Error _ -> ()

let merlin_locate ~fs ~process_mgr () =
  with_sample @@ fun file ->
  Atchoum.Merlin.locate ~fs ~process_mgr ~file ~line:2 ~col:8 ()
  |> check_ok ~sub:{|"pos":{"line":1,"col":4}|}
       ~msg:"x is defined at 1:4 in the same file"

let merlin_locate_prefix ~fs ~process_mgr () =
  with_sample @@ fun file ->
  Atchoum.Merlin.locate ~fs ~process_mgr ~prefix:"List.iter"
    ~look_for:`Interface ~file ~line:2 ~col:0 ()
  |> check_ok ~sub:"list.mli" ~msg:"List.iter is declared in list.mli"

let text_of (result : Mcp_kit.Tool.result) =
  String.concat ""
    (List.filter_map
       (function Mcp_kit.Tool.Text s -> Some s | _ -> None)
       result.content)

let position ?(extra = []) file ~line ~col =
  `Assoc
    ([ ("file", `String file); ("line", `Int line); ("col", `Int col) ] @ extra)

let tool_call ~fs ~process_mgr () =
  with_sample @@ fun file ->
  let result =
    Mcp_kit.Tool.call
      (Atchoum.Server.type_enclosing ~fs ~process_mgr)
      (position file ~line:1 ~col:4)
  in
  Alcotest.(check bool) "not an error" false result.is_error;
  Alcotest.(check bool)
    "text contains the type int" true
    (contains ~sub:{|"type":"int"|} (text_of result))

let tool_invalid_line ~fs ~process_mgr () =
  with_sample @@ fun file ->
  let result =
    Mcp_kit.Tool.call
      (Atchoum.Server.type_enclosing ~fs ~process_mgr)
      (position file ~line:0 ~col:4)
  in
  Alcotest.(check bool) "line 0 is rejected" true result.is_error

let tool_locate ~fs ~process_mgr () =
  with_sample @@ fun file ->
  let result =
    Mcp_kit.Tool.call
      (Atchoum.Server.locate ~fs ~process_mgr)
      (position file ~line:3 ~col:13
         ~extra:[ ("look_for", `String "interface") ])
  in
  Alcotest.(check bool) "not an error" false result.is_error;
  Alcotest.(check bool)
    "List.map is declared in list.mli" true
    (contains ~sub:"list.mli" (text_of result))

let tool_locate_invalid_look_for ~fs ~process_mgr () =
  with_sample @@ fun file ->
  let result =
    Mcp_kit.Tool.call
      (Atchoum.Server.locate ~fs ~process_mgr)
      (position file ~line:3 ~col:13 ~extra:[ ("look_for", `String "foo") ])
  in
  Alcotest.(check bool) "look_for foo is rejected" true result.is_error

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
        ] );
      ( "server",
        [
          case "type_enclosing call" tool_call;
          case "invalid line" tool_invalid_line;
          case "locate call" tool_locate;
          case "invalid look_for" tool_locate_invalid_look_for;
        ] );
    ]
