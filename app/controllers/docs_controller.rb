# frozen_string_literal: true

# Publishes the public catalog API reference at /docs/api, the MCP server
# guide at /docs/mcp, and the machine descriptions of the API at
# /docs/api/openapi.json and /docs/api/schema.graphql.
#
# Each page renders a file in docs/ (PAGES), the same file the repository
# keeps, so the site and the repository cannot say different things.
#
# An agent reads the markdown source, not the HTML. It gets the source from
# /docs/api.md, or from /docs/api when its Accept header ranks text/markdown
# above text/html. /docs/mcp works the same way.
#
# It inherits ActionController::Base, not ApplicationController. The page needs
# no sign-in and no Pundit, and the modern-browser guard on the app pages would
# refuse curl and any other script that reads the reference.
class DocsController < ActionController::Base
  include MarkdownNegotiation

  layout "docs"

  SOURCE    = Rails.root.join("docs/public-catalog-api.md")
  OPENAPI   = Rails.root.join("docs/public-catalog-api.openapi.yml")
  CACHE_AGE = 1.hour

  # One entry for each markdown page: its source file, title, and description.
  PAGES = {
    api: {
      source:      SOURCE,
      title:       "Course Catalog API",
      description: "Public read-only REST and GraphQL API for the Wentworth course catalog."
    },
    mcp: {
      source:      Rails.root.join("docs/mcp.md"),
      title:       "MCP Server",
      description: "Connect Claude, ChatGPT, or another MCP client to your Wentworth schedule."
    }
  }.freeze

  def api
    render_page(:api, api_docs_url)
  end

  def mcp
    render_page(:mcp, mcp_docs_url)
  end

  # The file names no host. The server URL comes from the request, the same as
  # the URLs in /llms.txt.
  def openapi
    expires_in CACHE_AGE, public: true

    document = YAML.safe_load_file(OPENAPI)
    document["servers"] = [ { "url" => root_url.delete_suffix("/") } ]

    render json: document, content_type: "application/vnd.oai.openapi+json"
  end

  # The SDL comes from the schema class that runs the queries, so it cannot
  # drift from the endpoint.
  def graphql_schema
    expires_in CACHE_AGE, public: true
    render plain: CatalogSchema.to_definition
  end

  # @return [Hash] the rendered HTML and the top-level headings, for the menu.
  def self.render_markdown(text)
    html = markdown.render(text)
    doc  = Nokogiri::HTML.fragment(html)

    headings = doc.css("h2").filter_map do |node|
      { id: node["id"], text: node.text } if node["id"].present?
    end

    make_scrollable(doc)

    { html: doc.to_html, headings: headings }
  end

  # A wide code block or table scrolls sideways inside itself. tabindex lets a
  # keyboard user focus it and scroll with the arrow keys. The table scrolls in
  # a wrapper, because display: block on the table removes its table role for
  # some screen readers.
  def self.make_scrollable(doc)
    doc.css("pre").each { |pre| pre["tabindex"] = "0" }

    doc.css("table").each do |table|
      table.wrap(%(<div class="docs-table" tabindex="0"></div>))
    end
  end
  private_class_method :make_scrollable

  # escape_html keeps any raw HTML in the source out of the page. The file is
  # ours, so this is a guard, not a filter that the document depends on.
  def self.markdown
    Redcarpet::Markdown.new(
      Redcarpet::Render::HTML.new(with_toc_data: true, escape_html: true),
      tables:             true,
      fenced_code_blocks: true,
      autolink:           true,
      strikethrough:      true,
      no_intra_emphasis:  true,
      space_after_headers: true
    )
  end
  private_class_method :markdown

  private

  def render_page(key, url)
    @page = PAGES.fetch(key).merge(url: url, markdown_url: "#{url}.md")
    source = @page[:source]
    raise ActionController::RoutingError, "No #{@page[:title]} page" unless source.exist?

    expires_in CACHE_AGE, public: true
    # The HTML and the markdown share one URL, so a cache must key on Accept.
    response.headers["Vary"] = "Accept"
    response.headers["Link"] = %(<#{@page[:markdown_url]}>; rel="alternate"; type="text/markdown")

    return render(plain: source.read, content_type: "text/markdown") if markdown_requested?

    document  = self.class.render_markdown(source.read)
    # Safe to mark: the source is a file in this repository, not user input, and
    # the renderer is configured with escape_html so any HTML inside the
    # markdown comes out escaped. Saying so here keeps the reasoning next to the
    # renderer rather than leaving a bare raw() in the template.
    @body     = document[:html].html_safe # rubocop:disable Rails/OutputSafety
    @headings = document[:headings]

    # A client that asks for neither format still gets the page.
    render :page, formats: :html
  end

  def markdown_requested?
    case params[:format]
    when "md"   then true
    when "html" then false
    when nil    then prefers_markdown?
    else raise ActionController::UnknownFormat
    end
  end

  # Markdown wins only when the client ranks it above HTML.
  def prefers_markdown?
    preferred_document_type == Mime[:md]
  end
end
