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

    it "does not disallow the public API or the reference" do
      get "/robots.txt", headers: crawler

      disallowed = response.body.scan(/^Disallow: (\S+)$/).flatten
      %w[/api/v1/catalog/terms /docs/api /docs/api.md /llms.txt /reports/sections].each do |path|
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

  describe "GET /.well-known/security.txt" do
    include ActiveSupport::Testing::TimeHelpers

    let(:fields) { response.body.lines.grep_v(/^#/).map { |line| line.chomp.split(": ", 2) } }

    it "answers with plain text" do
      get "/.well-known/security.txt", headers: crawler

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to eq("text/plain; charset=utf-8")
    end

    it "lists GitHub private reporting first, then the email contacts" do
      get "/.well-known/security.txt", headers: crawler

      contacts = fields.select { |name, _| name == "Contact" }.map(&:last)
      expect(contacts).to eq([
        "https://github.com/WITCodingClub/calendar-backend/security/advisories/new",
        "mailto:calendarwit@gmail.com",
        "mailto:lambertl@wit.edu",
        "mailto:mayonej@wit.edu"
      ])
    end

    it "expires in the future and less than one year ahead" do
      travel_to Time.utc(2026, 9, 13, 15, 30) do
        get "/.well-known/security.txt", headers: crawler
      end

      expires = fields.to_h.fetch("Expires")
      expect(expires).to eq("2027-09-01T00:00:00Z")
    end

    it "names its canonical URL on this host" do
      get "/.well-known/security.txt", headers: crawler

      expect(fields.to_h.fetch("Canonical")).to eq("http://example.com/.well-known/security.txt")
    end

    it "uses only the fields RFC 9116 defines" do
      get "/.well-known/security.txt", headers: crawler

      known = %w[Acknowledgments Canonical Contact Encryption Expires Hiring Policy Preferred-Languages CSAF]
      expect(fields.map(&:first).uniq - known).to be_empty
    end
  end
end
