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

(* [ocamlmerlin single COMMAND ARGS -position LINE:COL -filename FILE], with
   the contents of [file] on standard input. *)
let query ~fs ~process_mgr ~file ~line ~col command args =
  run ~fs ~process_mgr ~stdin_file:file
    (("single" :: command :: args)
    @ [ "-position"; Printf.sprintf "%d:%d" line col; "-filename"; file ])

let type_enclosing ~fs ~process_mgr ~file ~line ~col =
  query ~fs ~process_mgr ~file ~line ~col "type-enclosing" []

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
  query ~fs ~process_mgr ~file ~line ~col "locate" (prefix @ look_for)
