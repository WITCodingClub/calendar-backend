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

    it "links the masthead back to the site and to the other docs page" do
      get "/docs/api"

      page = Nokogiri::HTML(response.body)
      expect(page.at("header a.docs-brand")["href"]).to eq("/")
      expect(page.at('nav[aria-label="Docs"] a[aria-current="page"]')["href"]).to eq("/docs/api")
      expect(page.at('nav[aria-label="Docs"] a[href="/docs/mcp"]')["aria-current"]).to be_nil
    end

    it "lets a keyboard user skip to the article in <main>" do
      get "/docs/api"

      page = Nokogiri::HTML(response.body)
      expect(page.at("a.docs-skip")["href"]).to eq("#content")
      expect(page.at("main#content article")).to be_present
    end

    it "puts the menu in a <details>, so a phone shows it as one line" do
      get "/docs/api"

      page = Nokogiri::HTML(response.body)
      expect(page.at("details.docs-toc > summary").text).to eq("On this page")
      expect(page.at("details.docs-toc")["open"]).to be_nil
    end

    it "lets a keyboard user scroll code blocks and tables" do
      get "/docs/api"

      page = Nokogiri::HTML(response.body)
      expect(page.css("main pre")).to all(satisfy { |pre| pre["tabindex"] == "0" })
      expect(page.css("main table")).to all(satisfy { |table| table.parent["class"] == "docs-table" })
      expect(page.css("main table")).not_to be_empty
    end

    it "loads one exact Mermaid version, the same one the CSP allows" do
      get "/docs/api"

      url = Rails.configuration.x.mermaid_url
      expect(url).to match(%r{/mermaid@\d+\.\d+\.\d+/\z})
      expect(response.body).to include(%(import("#{url}dist/mermaid.esm.min.mjs")))
      expect(Rails.application.config.content_security_policy.directives["script-src"]).to include(url)
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

    # The HTML page also preloads its stylesheets in the same header.
    it "links every response to the markdown copy" do
      get "/docs/api"

      expect(response.headers["Link"])
        .to start_with('<http://example.com/docs/api.md>; rel="alternate"; type="text/markdown"')
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

  describe "diagrams" do
    # Mermaid turns accTitle and accDescr into the SVG <title> and <desc>, the
    # text alternative a screen reader reads.
    DocsController::PAGES.each do |key, page|
      it "gives each diagram on the #{key} page a text alternative" do
        diagrams = page[:source].read.scan(/^```mermaid\n(.*?)^```/m).flatten

        expect(diagrams).not_to be_empty
        expect(diagrams).to all(match(/^\s*accTitle: \S/).and(match(/^\s*accDescr: \S/)))
      end
    end
  end

  describe ".render_markdown" do
    it "gives every heading an id, so the menu can link to it" do
      document = DocsController.render_markdown("## Sections\n\ntext\n")

      expect(document[:headings]).to eq([ { id: "sections", text: "Sections" } ])
    end

    it "wraps a table in a focusable scroll box" do
      document = DocsController.render_markdown("| a | b |\n| - | - |\n| 1 | 2 |\n")

      wrapper = Nokogiri::HTML.fragment(document[:html]).at("div.docs-table")
      expect(wrapper["tabindex"]).to eq("0")
      expect(wrapper.at("> table")).to be_present
    end

    it "escapes raw HTML in the source" do
      document = DocsController.render_markdown("<script>alert(1)</script>\n")

      expect(document[:html]).not_to include("<script>")
    end
  end

  describe "GET /docs/mcp" do
    it "publishes the MCP guide from docs/mcp.md" do
      get "/docs/mcp"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("MCP Server", "my_busy_times")
      expect(response.body).to match(%r{<link rel="canonical" href="http://[^"]+/docs/mcp">})
    end

    it "returns the markdown source at /docs/mcp.md" do
      get "/docs/mcp.md"

      expect(response.media_type).to eq("text/markdown")
      expect(response.body).to eq(Rails.root.join("docs/mcp.md").read)
    end
  end
end
