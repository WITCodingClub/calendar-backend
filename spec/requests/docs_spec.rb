# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Docs", type: :request do
  describe "GET /docs/api" do
    it "publishes the reference without a sign-in" do
      get "/docs/api"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Course Catalog API")
    end

    it "renders the markdown, so the page holds no raw syntax" do
      get "/docs/api"

      expect(response.body).to include("<table>")
      expect(response.body).to include("<code>")
      expect(response.body).not_to include("| Parameter |")
    end

    it "shows the pub_id filter, so the file and the page agree" do
      get "/docs/api"

      expect(response.body).to include("pub_id")
    end

    it "builds a menu from the headings" do
      get "/docs/api"

      expect(response.body).to include('aria-label="On this page"')
      expect(response.body).to match(/<a href="#[a-z0-9-]+">/)
    end

    it "keeps the diagram source, so it renders or stays readable" do
      get "/docs/api"

      expect(response.body).to include('<code class="mermaid">')
    end

    it "lets a proxy cache the page" do
      get "/docs/api"

      expect(response.headers["Cache-Control"]).to include("public")
    end

    it "sends a client to the reference from /docs" do
      get "/docs"

      expect(response).to redirect_to("/docs/api")
    end

    it "gives search engines a canonical URL and a markdown alternate" do
      get "/docs/api"

      expect(response.body).to include('<link rel="canonical" href="http://example.com/docs/api">')
      expect(response.body).to include(
        '<link rel="alternate" type="text/markdown" href="http://example.com/docs/api.md">'
      )
    end

    it "gives link previews a title and a description" do
      get "/docs/api"

      page = Nokogiri::HTML(response.body)
      expect(page.at('meta[property="og:title"]')["content"]).to eq("Course Catalog API")
      expect(page.at('meta[property="og:url"]')["content"]).to eq("http://example.com/docs/api")
      expect(page.at('meta[property="og:description"]')["content"])
        .to eq(page.at('meta[name="description"]')["content"])
    end

    it "describes the page with structured data" do
      get "/docs/api"

      script = Nokogiri::HTML(response.body).at('script[type="application/ld+json"]')
      data   = JSON.parse(script.text)

      expect(data).to include("@type" => "TechArticle", "headline" => "Course Catalog API")
      expect(data.dig("encoding", "contentUrl")).to eq("http://example.com/docs/api.md")
    end
  end

  describe "markdown for agents" do
    let(:source) { DocsController::SOURCE.read }

    it "returns the markdown source from /docs/api.md" do
      get "/docs/api.md"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/markdown")
      expect(response.charset).to eq("utf-8")
      expect(response.body).to eq(source)
    end

    it "returns the markdown source to a client that asks for markdown only" do
      get "/docs/api", headers: { "Accept" => "text/markdown" }

      expect(response.media_type).to eq("text/markdown")
      expect(response.body).to eq(source)
    end

    it "returns the markdown source to an agent that also accepts anything" do
      get "/docs/api", headers: { "Accept" => "text/markdown, text/html, */*" }

      expect(response.media_type).to eq("text/markdown")
    end

    it "returns the markdown source when markdown has the higher quality" do
      get "/docs/api", headers: { "Accept" => "text/html;q=0.5, text/markdown" }

      expect(response.media_type).to eq("text/markdown")
    end

    it "returns the page to a browser" do
      accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
      get "/docs/api", headers: { "Accept" => accept }

      expect(response.media_type).to eq("text/html")
    end

    it "returns the page when HTML has the higher quality" do
      get "/docs/api", headers: { "Accept" => "text/html, text/markdown;q=0.5" }

      expect(response.media_type).to eq("text/html")
    end

    # Rails skips a header that lists */*, so only the controller parses this one.
    it "returns the page when the Accept header is not valid" do
      get "/docs/api", headers: { "Accept" => "text/markdown, garbage, */*" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
    end

    it "tells a cache that the response depends on Accept" do
      get "/docs/api"
      expect(response.headers["Vary"]).to eq("Accept")

      get "/docs/api", headers: { "Accept" => "text/markdown, */*" }
      expect(response.headers["Vary"]).to eq("Accept")
    end

    it "links every response to the markdown copy" do
      get "/docs/api"

      expect(response.headers["Link"])
        .to eq('<http://example.com/docs/api.md>; rel="alternate"; type="text/markdown"')
    end

    it "lets a proxy cache the markdown" do
      get "/docs/api.md"

      expect(response.headers["Cache-Control"]).to include("public")
    end

    it "refuses a format the reference does not have" do
      get "/docs/api.json"

      expect(response).to have_http_status(:not_acceptable)
    end
  end

  describe ".render_markdown" do
    it "gives every heading an id, so the menu can link to it" do
      document = DocsController.render_markdown("## Sections\n\ntext\n")

      expect(document[:headings]).to eq([ { id: "sections", text: "Sections" } ])
    end

    it "escapes raw HTML in the source" do
      document = DocsController.render_markdown("<script>alert(1)</script>\n")

      expect(document[:html]).not_to include("<script>")
    end
  end
end
