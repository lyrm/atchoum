(lang dune 3.17)

(name atchoum)

(generate_opam_files true)

(license MIT)

(authors "Carine Morel")

(maintainers "Carine Morel <lyrm@github.com>")

(package
 (name atchoum)
 (synopsis "Merlin-powered MCP server for Claude Code")
 (description
  "A Claude Code plugin whose MCP server exposes Merlin queries as tools, so that Claude navigates and edits OCaml code through Merlin rather than through text-based tools such as grep or sed.")
 (depends
  (ocaml
   (>= 5.2))
  (mcp-kit
   (and
    (>= 0.2.0)
    (< 0.3)))
  (mcp-kit-eio
   (and
    (>= 0.2.0)
    (< 0.3)))
  (eio
   (>= 1.6))
  (yojson
   (>= 2.0))
  (eio_main
   (>= 1.6))
  (alcotest :with-test)
  (merlin :with-test)
  (ocamlformat
   (and
    :with-dev-setup
    (= 0.29.0)))
  (ocaml-lsp-server :with-dev-setup)))
