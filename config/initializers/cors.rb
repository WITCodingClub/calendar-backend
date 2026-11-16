# frozen_string_literal: true

require Rails.root.join("app/lib/request_paths")

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  # The MCP server and its OAuth endpoints (docs/mcp.md). A bearer token, not
  # a cookie, signs these requests in, so any origin may call them, and
  # credentials stay false. A browser client must read WWW-Authenticate to
  # find the sign-in. First, so the localhost rule below does not take /api/mcp.
  allow do
    origins "*"

    resource RequestPaths::MCP,
             headers: :any,
             methods: [ :post, :options ],
             credentials: false,
             expose: [ "WWW-Authenticate", "Mcp-Session-Id" ]

    RequestPaths::OAUTH_CLIENT.each do |path|
      resource path, headers: :any, methods: [ :post, :options ], credentials: false
    end

    resource "#{RequestPaths::OAUTH_METADATA_PREFIX}*",
             headers: :any,
             methods: [ :get, :options, :head ],
             credentials: false
  end

  # The public catalog API carries no credentials and no user data, so any
  # origin may read it. credentials must stay false to pair with origins "*".
  # Cloudflare caches these responses for every origin (#684), so each one
  # must be the same: this rule comes before the localhost rule, and
  # Api::V1::PublicController sends the header when a request has no Origin.
  allow do
    origins "*"

    # The schedule builder takes its input in a POST body. It comes before
    # the catalog rule, because Rack::Cors uses the first resource that
    # matches the path.
    # expose: a browser on another origin can read Retry-After of a 503.
    resource "#{RequestPaths::PUBLIC_CATALOG_PREFIX}/schedule_options*",
             headers: :any,
             methods: [ :post, :options ],
             credentials: false,
             expose: [ "Retry-After" ]

    resource "#{RequestPaths::PUBLIC_CATALOG_PREFIX}/*",
             headers: :any,
             methods: [ :get, :options, :head ],
             credentials: false
  end

  allow do
    origins_list = [
      "http://localhost:3001",
      "https://localhost:3001",
      /\Ahttps?:\/\/localhost:\d+\z/
    ]
    origins_list << /\Achrome-extension:\/\/.+\z/ if Rails.env.development?

    origins(*origins_list)

    resource "/api/*",
             headers: :any,
             methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
             credentials: true,
             expose: [ "Authorization" ]
  end

  # The public GraphQL API carries no credentials and no user data, so any
  # origin may read it. credentials must stay false to pair with origins "*".
  allow do
    origins "*"

    # The old path answers 308 to /api/v1/graphql. A browser follows the
    # redirect only when this response also allows the origin.
    RequestPaths::GRAPHQL.each do |path|
      resource path, headers: :any, methods: [ :post, :options, :head ], credentials: false
    end
  end
end
