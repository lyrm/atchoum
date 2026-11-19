[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

type t = { file : string; edit : Merlin.edit }

let ( let* ) = Result.bind

(* Byte offset of each line start (line 1 at index 0). *)
let line_starts text =
  let starts = ref [ 0 ] in
  String.iteri (fun i c -> if c = '\n' then starts := (i + 1) :: !starts) text;
  Array.of_list (List.rev !starts)

let offset starts text { Merlin.line; col } =
  if line < 1 || line > Array.length starts then
    Error (Printf.sprintf "line %d is out of the file" line)
  else
    let o = starts.(line - 1) + col in
    if o > String.length text then
      Error (Printf.sprintf "position %d:%d is out of the file" line col)
    else Ok o

let slice text { Merlin.start; stop } =
  let starts = line_starts text in
  let* a = offset starts text start in
  let* b = offset starts text stop in
  if b < a then Error "empty range" else Ok (String.sub text a (b - a))

(* Apply [edits] to [text]: from the last to the first, so that offsets stay
   valid; overlapping edits are refused. *)
let apply_to_text text (edits : Merlin.edit list) =
  let starts = line_starts text in
  let* spans =
    List.fold_left
      (fun acc (e : Merlin.edit) ->
        let* acc = acc in
        let* a = offset starts text e.range.start in
        let* b = offset starts text e.range.stop in
        Ok ((a, b, e.text) :: acc))
      (Ok []) edits
  in
  let spans = List.sort (fun (a, _, _) (b, _, _) -> compare b a) spans in
  let rec check = function
    | (a, _, _) :: ((_, b', _) :: _ as rest) ->
        if b' > a then Error "overlapping edits" else check rest
    | _ -> Ok ()
  in
  let* () = check spans in
  Ok
    (List.fold_left
       (fun text (a, b, s) ->
         String.sub text 0 a ^ s ^ String.sub text b (String.length text - b))
       text spans)

let group edits =
  List.fold_left
    (fun acc { file; edit } ->
      match List.assoc_opt file acc with
      | Some es -> (file, edit :: es) :: List.remove_assoc file acc
      | None -> (file, [ edit ]) :: acc)
    [] edits
  |> List.rev

let apply ~fs edits =
  let files = group edits in
  (* Compute every new content before writing any file. *)
  let* contents =
    List.fold_left
      (fun acc (file, es) ->
        let* acc = acc in
        let path = Eio.Path.(fs / file) in
        let* text =
          try Ok (Eio.Path.load path)
          with Eio.Io _ as e -> Error (Printexc.to_string e)
        in
        let* text =
          Result.map_error (fun m -> file ^ ": " ^ m) (apply_to_text text es)
        in
        Ok ((path, text) :: acc))
      (Ok []) files
  in
  try
    List.iter
      (fun (path, text) -> Eio.Path.save ~create:`Never path text)
      contents;
    Ok (List.map fst files)
  with Eio.Io _ as e -> Error (Printexc.to_string e)
