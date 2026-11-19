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
type location = { file : string; pos : position }

let ( let* ) = Result.bind
let shorten s = if String.length s <= 300 then s else String.sub s 0 300 ^ "..."

let unexpected what =
  Error ("unexpected answer from ocamlmerlin: " ^ shorten what)

(* Merlin answers [{"class": C, "value": V, ...}] where C is "return" on
   success and "failure", "error" or "exception" otherwise; the other fields
   (timing, cache, ...) are dropped. *)
let answer_value out =
  match Yojson.Safe.from_string out with
  | exception Yojson.Json_error _ -> unexpected out
  | `Assoc fields -> (
      match (List.assoc_opt "class" fields, List.assoc_opt "value" fields) with
      | Some (`String "return"), Some value -> Ok value
      | Some (`String cls), Some (`String msg) ->
          Error (Printf.sprintf "merlin %s: %s" cls msg)
      | Some (`String cls), Some value ->
          Error
            (Printf.sprintf "merlin %s: %s" cls
               (shorten (Yojson.Safe.to_string value)))
      | _ -> unexpected out)
  | _ -> unexpected out

(* [ocamlmerlin single COMMAND ARGS -position LINE:COL -filename FILE], with
   the contents of [file] on standard input; the answer's value. *)
let query ~fs ~process_mgr ~file ~line ~col command args =
  let* out =
    run ~fs ~process_mgr ~stdin_file:file
      (("single" :: command :: args)
      @ [ "-position"; Printf.sprintf "%d:%d" line col; "-filename"; file ])
  in
  answer_value out

(* The value is the list of enclosing expressions, innermost first. *)
let type_enclosing ~fs ~process_mgr ~file ~line ~col =
  let* value = query ~fs ~process_mgr ~file ~line ~col "type-enclosing" [] in
  match value with
  | `List (`Assoc innermost :: _) -> (
      match List.assoc_opt "type" innermost with
      | Some (`String ty) -> Ok ty
      | _ -> unexpected (Yojson.Safe.to_string value))
  | `List [] -> Error "no expression at this position"
  | _ -> unexpected (Yojson.Safe.to_string value)

let position_of_json = function
  | `Assoc fields -> (
      match (List.assoc_opt "line" fields, List.assoc_opt "col" fields) with
      | Some (`Int line), Some (`Int col) -> Some { line; col }
      | _ -> None)
  | _ -> None

(* The value is [{"file": F, "pos": P}], or a string explaining why the
   definition was not found. A relative [F] (the queried buffer itself) is
   resolved against the queried file's directory. *)
let location_of_value ~file value =
  match value with
  | `String reason -> Error reason
  | `Assoc fields -> (
      let found =
        match List.assoc_opt "file" fields with
        | Some (`String f) when Filename.is_relative f ->
            Filename.concat (Filename.dirname file) f
        | Some (`String f) -> f
        | _ -> file
      in
      match Option.bind (List.assoc_opt "pos" fields) position_of_json with
      | Some pos -> Ok { file = found; pos }
      | None -> unexpected (Yojson.Safe.to_string value))
  | _ -> unexpected (Yojson.Safe.to_string value)

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
    query ~fs ~process_mgr ~file ~line ~col "locate" (prefix @ look_for)
  in
  location_of_value ~file value
