; extends

((inline) @injection.content
  (#lua-match? @injection.content "{{")
  (#set! injection.language "glimmer"))
