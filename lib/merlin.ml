[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

let string_of_status = function
  | `Exited n -> Printf.sprintf "exit code %d" n
  | `Signaled n -> Printf.sprintf "killed by signal %d" n

(* Run [ocamlmerlin args] with [stdin_file] as its standard input. Both output
   streams are captured: the child must never inherit our standard output,
   which carries the MCP JSON-RPC stream. The buffers are read only once the
   switch has finished, that is once Eio's copying fibers are done. *)
let run ~fs ~process_mgr ~stdin_file args =
  let out = Buffer.create 4096 and err = Buffer.create 256 in
  match
    Eio.Path.with_open_in Eio.Path.(fs / stdin_file) @@ fun stdin ->
    Eio.Switch.run @@ fun sw ->
    let child =
      Eio.Process.spawn ~sw process_mgr ~stdin
        ~stdout:(Eio.Flow.buffer_sink out) ~stderr:(Eio.Flow.buffer_sink err)
        ("ocamlmerlin" :: args)
    in
    Eio.Process.await child
  with
  | _ when Buffer.length out > 0 -> Ok (Buffer.contents out)
  | status ->
      let err = String.trim (Buffer.contents err) in
      Error
        (Printf.sprintf "ocamlmerlin produced no output (%s)%s"
           (string_of_status status)
           (if err = "" then "" else ":\n" ^ err))
  | exception (Eio.Io _ as e) -> Error (Printexc.to_string e)

type position = { line : int; col : int }
type range = { start : position; stop : position }
type location = { file : string; pos : position }

let ( let* ) = Result.bind
let shorten s = if String.length s <= 300 then s else String.sub s 0 300 ^ "..."

let unexpected json =
  Error
    ("unexpected answer from ocamlmerlin: "
    ^ shorten (Yojson.Safe.to_string json))

(* Merlin answers [{"class": C, "value": V, ...}] where C is "return" on
   success and "failure", "error" or "exception" otherwise; the other fields
   (timing, cache, ...) are dropped. *)
let answer_value out =
  match Yojson.Safe.from_string out with
  | exception Yojson.Json_error _ ->
      Error ("unexpected output from ocamlmerlin: " ^ shorten out)
  | `Assoc fields as json -> (
      match (List.assoc_opt "class" fields, List.assoc_opt "value" fields) with
      | Some (`String "return"), Some value -> Ok value
      | Some (`String cls), Some (`String msg) ->
          Error (Printf.sprintf "merlin %s: %s" cls msg)
      | Some (`String cls), Some value ->
          Error
            (Printf.sprintf "merlin %s: %s" cls
               (shorten (Yojson.Safe.to_string value)))
      | _ -> unexpected json)
  | json -> unexpected json

let pos_arg { line; col } = Printf.sprintf "%d:%d" line col

(* [ocamlmerlin single COMMAND ARGS -filename FILE], with the contents of
   [file] on standard input; the answer's value. *)
let query ~fs ~process_mgr ~file command args =
  let* out =
    run ~fs ~process_mgr ~stdin_file:file
      (("single" :: command :: args) @ [ "-filename"; file ])
  in
  answer_value out

(* JSON decoding helpers. *)

let field name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let string_field name json =
  match field name json with Some (`String s) -> Some s | _ -> None

let position_of_json json =
  match (field "line" json, field "col" json) with
  | Some (`Int line), Some (`Int col) -> Some { line; col }
  | _ -> None

let range_of_json json =
  match
    ( Option.bind (field "start" json) position_of_json,
      Option.bind (field "end" json) position_of_json )
  with
  | Some start, Some stop -> Some { start; stop }
  | _ -> None

let list_of value f =
  match value with
  | `List items -> (
      let decoded = List.filter_map f items in
      match List.length decoded = List.length items with
      | true -> Ok decoded
      | false -> unexpected value)
  | _ -> unexpected value

(* A relative file in an answer is the queried buffer itself. *)
let resolve ~file f =
  if Filename.is_relative f then Filename.concat (Filename.dirname file) f
  else f

(* Queries. *)

let type_enclosing ~fs ~process_mgr ?(expand = false) ~file ~line ~col () =
  let verbosity = if expand then [ "-verbosity"; "1" ] else [] in
  let* value =
    query ~fs ~process_mgr ~file "type-enclosing"
      ([ "-position"; pos_arg { line; col } ] @ verbosity)
  in
  (* The list of enclosing expressions, innermost first. *)
  match value with
  | `List (innermost :: _) -> (
      match string_field "type" innermost with
      | Some ty -> Ok ty
      | None -> unexpected value)
  | `List [] -> Error "no expression at this position"
  | _ -> unexpected value

(* [{"file": F, "pos": P}], or a string explaining why it was not found. *)
let location_of_value ~file = function
  | `String reason -> Error reason
  | value -> (
      let found =
        Option.fold ~none:file ~some:(resolve ~file) (string_field "file" value)
      in
      match Option.bind (field "pos" value) position_of_json with
      | Some pos -> Ok { file = found; pos }
      | None -> unexpected value)

let locate ~fs ~process_mgr ?prefix ?look_for ~file ~line ~col () =
  let prefix =
    match prefix with None -> [] | Some prefix -> [ "-prefix"; prefix ]
  in
  let look_for =
    match look_for with
    | None -> []
    | Some `Interface -> [ "-look-for"; "interface" ]
    | Some `Implementation -> [ "-look-for"; "implementation" ]
  in
  let* value =
    query ~fs ~process_mgr ~file "locate"
      ([ "-position"; pos_arg { line; col } ] @ prefix @ look_for)
  in
  location_of_value ~file value

let locate_type ~fs ~process_mgr ~file ~line ~col =
  let* value =
    query ~fs ~process_mgr ~file "locate-type"
      [ "-position"; pos_arg { line; col } ]
  in
  match value with
  | `Assoc _ -> (
      (* Either [{"file", "pos": P}] or [{"file", "pos": {"start", "end"}}]. *)
      let found =
        Option.fold ~none:file ~some:(resolve ~file) (string_field "file" value)
      in
      let pos = field "pos" value in
      match
        ( Option.bind pos position_of_json,
          Option.bind (Option.bind pos (field "start")) position_of_json )
      with
      | Some pos, _ | None, Some pos -> Ok { file = found; pos }
      | None, None -> unexpected value)
  | value -> location_of_value ~file value

let document ~fs ~process_mgr ~file ~line ~col =
  let* value =
    query ~fs ~process_mgr ~file "document"
      [ "-position"; pos_arg { line; col } ]
  in
  match value with `String doc -> Ok doc | _ -> unexpected value

let type_expression ~fs ~process_mgr ~file ~line ~col ~expression =
  let* value =
    query ~fs ~process_mgr ~file "type-expression"
      [ "-position"; pos_arg { line; col }; "-expression"; expression ]
  in
  match value with `String ty -> Ok ty | _ -> unexpected value

type error = { range : range option; kind : string; message : string }

let errors ~fs ~process_mgr ~file =
  let* value = query ~fs ~process_mgr ~file "errors" [] in
  list_of value (fun e ->
      Option.map
        (fun message ->
          {
            range = range_of_json e;
            kind = Option.value ~default:"error" (string_field "type" e);
            message;
          })
        (string_field "message" e))

type outline_item = {
  name : string;
  kind : string;
  typ : string option;
  range : range;
  children : outline_item list;
}

let rec outline_item json =
  match
    (string_field "name" json, string_field "kind" json, range_of_json json)
  with
  | Some name, Some kind, Some range ->
      let children =
        match field "children" json with
        | Some (`List cs) -> List.filter_map outline_item cs
        | _ -> []
      in
      Some
        {
          name;
          kind;
          typ = string_field "type" json;
          range;
          children = List.sort compare_items children;
        }
  | _ -> None

and compare_items a b = compare a.range.start b.range.start

let outline ~fs ~process_mgr ~file =
  let* value = query ~fs ~process_mgr ~file "outline" [] in
  let* items = list_of value outline_item in
  Ok (List.sort compare_items items)

type occurrence = { file : string; range : range; stale : bool }

let occurrences ~fs ~process_mgr ~scope ~file ~line ~col =
  let scope =
    match scope with
    | `Buffer -> "buffer"
    | `Project -> "project"
    | `Renaming -> "renaming"
  in
  let* value =
    query ~fs ~process_mgr ~file "occurrences"
      [ "-identifier-at"; pos_arg { line; col }; "-scope"; scope ]
  in
  list_of value (fun o ->
      Option.map
        (fun range ->
          {
            file =
              Option.fold ~none:file ~some:(resolve ~file)
                (string_field "file" o);
            range;
            stale = field "stale" o = Some (`Bool true);
          })
        (range_of_json o))

type search_result = { name : string; typ : string; where : location option }

let search_by_type ~fs ~process_mgr ~file ~line ~col ~query:q ~limit =
  let* value =
    query ~fs ~process_mgr ~file "search-by-type"
      [
        "-position";
        pos_arg { line; col };
        "-query";
        q;
        "-limit";
        string_of_int limit;
        "-with-doc";
        "false";
      ]
  in
  let* results =
    list_of value (fun r ->
        match (string_field "name" r, string_field "type" r) with
        | Some name, Some typ ->
            let where =
              match
                ( string_field "file" r,
                  Option.bind (field "start" r) position_of_json )
              with
              | Some f, Some pos -> Some { file = f; pos }
              | _ -> None
            in
            Some { name; typ; where }
        | _ -> None)
  in
  (* Merlin lists some entries twice. *)
  let rec dedup seen = function
    | [] -> []
    | r :: rs when List.mem (r.name, r.typ) seen -> dedup seen rs
    | r :: rs -> r :: dedup ((r.name, r.typ) :: seen) rs
  in
  Ok (dedup [] results)

type edit = { range : range; text : string }

(* [[range, text]]: the text replacing the range. *)
let case_analysis ~fs ~process_mgr ~file ~start ~stop =
  let* value =
    query ~fs ~process_mgr ~file "case-analysis"
      [ "-start"; pos_arg start; "-end"; pos_arg stop ]
  in
  match value with
  | `List [ r; `String text ] -> (
      match range_of_json r with
      | Some range -> Ok { range; text }
      | None -> unexpected value)
  | _ -> unexpected value

(* [[range, [candidate; ...]]] for the hole at the position. *)
let construct ~fs ~process_mgr ?depth ~file ~line ~col () =
  let depth =
    match depth with None -> [] | Some d -> [ "-depth"; string_of_int d ]
  in
  let* value =
    query ~fs ~process_mgr ~file "construct"
      ([ "-position"; pos_arg { line; col } ] @ depth)
  in
  match value with
  | `List [ r; `List candidates ] -> (
      match range_of_json r with
      | Some range ->
          Ok
            ( range,
              List.filter_map
                (function `String c -> Some c | _ -> None)
                candidates )
      | None -> unexpected value)
  | _ -> unexpected value

let refactor_open ~fs ~process_mgr ~action ~file ~line ~col =
  let action =
    match action with `Qualify -> "qualify" | `Unqualify -> "unqualify"
  in
  let* value =
    query ~fs ~process_mgr ~file "refactor-open"
      [ "-position"; pos_arg { line; col }; "-action"; action ]
  in
  list_of value (fun e ->
      match (range_of_json e, string_field "content" e) with
      | Some range, Some text -> Some { range; text }
      | _ -> None)
