(fenced_code_block
  (info_string
    (language) @injection.language)
  (code_fence_content) @injection.content)

((fenced_code_block
  (info_string (language) @_language)
  (code_fence_content) @injection.content)
  (#eq? @_language "math")
  (#set! injection.language "latex"))

((html_block) @injection.content
  (#set! injection.language "html")
  (#set! injection.combined)
  (#set! injection.include-children))

((minus_metadata) @injection.content
  (#set! injection.language "glimmer")
  (#offset! @injection.content 1 0 -1 0)
  (#set! injection.include-children))

((plus_metadata) @injection.content
  (#set! injection.language "toml")
  (#offset! @injection.content 1 0 -1 0)
  (#set! injection.include-children))

([
  (inline)
  (pipe_table_cell)
] @injection.content
  (#set! injection.language "markdown_inline"))

((inline) @injection.content
  (#lua-match? @injection.content "{{")
  (#set! injection.combined)
  (#set! injection.language "glimmer"))
