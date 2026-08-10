; extends

((template
  [
    (text_node) @injection.content
    (block_statement
      program: (text_node) @injection.content)
  ]) @_template
  (#lua-match? @_template "^[%w_-]+:.-\n[%w_-]+:")
  (#set! injection.combined)
  (#set! injection.language "yaml"))
