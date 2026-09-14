# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Discovery files", type: :request do
  # A crawler that the modern-browser guard does not know.
  let(:crawler) { { "User-Agent" => "curl/8.7.1" } }

  describe "GET /robots.txt" do
    it "answers a crawler with plain text" do
      get "/robots.txt", headers: crawler

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/plain")
    end

    it "allows every crawler to read the public pages" do
      get "/robots.txt", headers: crawler

      expect(response.body).to include("User-agent: *\nAllow: /\n")
      expect(response.body).not_to match(/^Disallow: \/$/)
    end

    it "keeps crawlers out of the pages that need a sign-in or a calendar token" do
      get "/robots.txt", headers: crawler

      %w[/admin /dashboard /users/ /calendar/].each do |path|
        expect(response.body).to include("Disallow: #{path}\n")
      end
    end

    it "declares content signals for every crawler" do
      get "/robots.txt", headers: crawler

      group = response.body[/^User-agent: \*\n(?:[^\n]+\n)*/]
      expect(group).to include("Content-Signal: search=yes, ai-input=yes, ai-train=no\n")
    end

    it "does not disallow the public API or the reference" do
      get "/robots.txt", headers: crawler

      disallowed = response.body.scan(/^Disallow: (\S+)$/).flatten
      %w[/api/v1/catalog/terms /docs/api /docs/api.md /llms.txt /auth.md /reports/sections].each do |path|
        expect(disallowed.none? { |prefix| path.start_with?(prefix) }).to be(true), "#{path} is disallowed"
      end
    end

    it "points crawlers at the sitemap on this host" do
      get "/robots.txt", headers: crawler

      expect(response.body).to include("Sitemap: http://example.com/sitemap.xml")
    end

    it "lets a proxy cache the file" do
      get "/robots.txt", headers: crawler

      expect(response.headers["Cache-Control"]).to include("public")
    end
  end

  describe "GET /sitemap.xml" do
    it "lists the API reference" do
      get "/sitemap.xml", headers: crawler

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/xml")

      locations = Nokogiri::XML(response.body).remove_namespaces!.xpath("//url/loc").map(&:text)
      expect(locations).to eq([ "http://example.com/docs/api" ])
    end
  end

  describe "GET /llms.txt" do
    let(:links) { response.body.scan(/\]\((http[^)]+)\)/).flatten }

    it "gives agents a markdown index of the site" do
      get "/llms.txt", headers: crawler

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/plain")
      expect(response.body).to start_with("# WIT Calendar\n\n> ")
    end

    it "sends agents to the markdown copy of the reference" do
      get "/llms.txt", headers: crawler

      expect(links).to include("http://example.com/docs/api.md")
    end

    it "sends agents to auth.md" do
      get "/llms.txt", headers: crawler

      expect(links).to include("http://example.com/auth.md")
    end

    it "links only to routes that exist" do
      get "/llms.txt", headers: crawler

      expect(links).not_to be_empty
      links.each do |link|
        path   = URI(link).path
        method = path == "/api/graphql" ? :post : :get
        route  = Rails.application.routes.recognize_path(path, method: method)

        expect(route[:controller]).not_to eq("api/catch_all"), "#{link} has no route"
      end
    end
  end

  describe "GET /.well-known/api-catalog" do
    let(:catalog) { JSON.parse(response.body) }

    it "answers with a linkset in the RFC 9727 media type" do
      get "/.well-known/api-catalog", headers: crawler

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to start_with(
        'application/linkset+json; profile="https://www.rfc-editor.org/info/rfc9727"'
      )
    end

    it "lists the REST API and the GraphQL API on this host" do
      get "/.well-known/api-catalog", headers: crawler

      expect(catalog["linkset"].pluck("anchor")).to eq(
        [ "http://example.com/api/v1/catalog", "http://example.com/api/graphql" ]
      )
    end

    it "gives each API a description, a reference, and a health check" do
      get "/.well-known/api-catalog", headers: crawler

      catalog["linkset"].each do |entry|
        %w[service-desc service-doc status].each do |relation|
          expect(entry[relation]).to be_present, "#{entry['anchor']} has no #{relation}"
        end
      end
    end

    it "links only to URLs that answer" do
      get "/.well-known/api-catalog", headers: crawler
      hrefs = catalog["linkset"].flat_map { |entry| entry.except("anchor").values.flatten.pluck("href") }.uniq

      hrefs.each do |href|
        get URI(href).path, headers: crawler

        expect(response).to have_http_status(:ok), "#{href} answered #{response.status}"
      end
    end

    it "names itself in a Link header, so a HEAD request finds it" do
      head "/.well-known/api-catalog", headers: crawler

      expect(response).to have_http_status(:ok)
      expect(response.headers["Link"]).to eq('<http://example.com/.well-known/api-catalog>; rel="api-catalog"')
    end

    it "lets a proxy cache the file" do
      get "/.well-known/api-catalog", headers: crawler

      expect(response.headers["Cache-Control"]).to include("public")
    end
  end

  describe "GET /auth.md" do
    before { get "/auth.md", headers: crawler }

    it "answers an agent with markdown under an auth.md heading" do
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/markdown")
      expect(response.body.lines.first).to match(/\A# .*auth\.md$/)
    end

    it "names the audience, the methods, and how to send the credential" do
      expect(response.body).to include("## Audience", "## Supported methods", "## Using the credential")
      expect(response.body).to include("POST http://example.com/api/user/onboard")
      expect(response.body).to include("POST http://example.com/api/user/passkeys/authenticate")
      expect(response.body).to include("Authorization: Bearer <jwt>")
    end

    it "lists every token error code that the API returns" do
      source = Rails.root.join("app/controllers/concerns/json_web_token_authenticatable.rb").read
      codes  = source.scan(/code: "(AUTH_[A-Z_]+)"/).flatten.uniq

      expect(codes).not_to be_empty
      codes.each { |code| expect(response.body).to include("`#{code}`") }
    end

    it "names only endpoints that exist" do
      endpoints = response.body.scan(%r{(GET|POST|DELETE) http://example\.com(/[^\s`]+)})

      expect(endpoints).not_to be_empty
      endpoints.each do |verb, path|
        # A placeholder such as {session_id} stands for any id.
        route = Rails.application.routes.recognize_path(path.gsub(/\{\w+\}/, "1"), method: verb.downcase.to_sym)

        expect(route[:controller]).not_to eq("api/catch_all"), "#{verb} #{path} has no route"
      end
    end

    it "links only to routes that exist" do
      links = response.body.scan(/\]\((http[^)]+)\)/).flatten

      expect(links).not_to be_empty
      links.each do |link|
        path   = URI(link).path
        method = path == "/api/graphql" ? :post : :get
        route  = Rails.application.routes.recognize_path(path, method: method)

        expect(route[:controller]).not_to eq("api/catch_all"), "#{link} has no route"
      end
    end

    it "lets a proxy cache the file" do
      expect(response.headers["Cache-Control"]).to include("public")
    end
  end
end
