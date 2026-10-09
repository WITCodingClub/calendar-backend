# frozen_string_literal: true

# Public pages: discovery files, the API reference, and meeting link pages.

# Files for search engines and AI agents
get "/robots.txt",  to: "discovery#robots",  as: :robots,  format: false, defaults: { format: :text }
get "/sitemap.xml", to: "discovery#sitemap", as: :sitemap, format: false, defaults: { format: :xml }
get "/llms.txt",    to: "discovery#llms",    as: :llms,    format: false, defaults: { format: :text }
get "/auth.md",     to: "discovery#auth",    as: :auth_md, format: false, defaults: { format: :md }

# RFC 9727 API catalog: the list of public APIs that an agent reads first.
get "/.well-known/api-catalog", to: "discovery#api_catalog", as: :api_catalog, format: false

# RFC 9116 security.txt: where to report a vulnerability.
get "/.well-known/security.txt", to: "discovery#security", as: :security_txt, format: false, defaults: { format: :text }

# Public API reference, rendered from docs/public-catalog-api.md.
# /docs/api.md, or Accept: text/markdown, returns the markdown source.
get "/docs",     to: redirect("/docs/api")
get "/docs/api", to: "docs#api", as: :api_docs
# Machine descriptions of the same API, for code generators and agents.
get "/docs/api/openapi.json",   to: "docs#openapi",        as: :api_openapi,        format: false
get "/docs/api/schema.graphql", to: "docs#graphql_schema", as: :api_graphql_schema, format: false

# One-time meeting link page (public, token-gated). A guest picks one time.
get  "/meet/:token", to: "meeting_links#show",   as: :meeting_link
post "/meet/:token", to: "meeting_links#create", as: :book_meeting_link
get  "/meet/:token/sign_in", to: "meeting_links#start_sign_in", as: :meeting_link_sign_in
