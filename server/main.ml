[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

let () =
  Eio_main.run @@ fun env ->
  let server =
    Atchoum.Server.create ~fs:(Eio.Stdenv.fs env)
      ~process_mgr:(Eio.Stdenv.process_mgr env)
      ()
  in
  Mcp_kit_eio.run_flow server ~input:(Eio.Stdenv.stdin env)
    ~output:(Eio.Stdenv.stdout env)
