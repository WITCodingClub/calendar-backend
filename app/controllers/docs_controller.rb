# frozen_string_literal: true

# Publishes the public catalog API reference at /docs/api.
#
# The page renders docs/public-catalog-api.md, the same file the repository
# keeps, so the site and the repository cannot say different things.
#
# An agent reads the markdown source, not the HTML. It gets the source from
# /docs/api.md, or from /docs/api when its Accept header ranks text/markdown
# above text/html.
#
# It inherits ActionController::Base, not ApplicationController. The page needs
# no sign-in and no Pundit, and the modern-browser guard on the app pages would
# refuse curl and any other script that reads the reference.
class DocsController < ActionController::Base
  layout "docs"

  SOURCE    = Rails.root.join("docs/public-catalog-api.md")
  CACHE_AGE = 1.hour

  def api
    raise ActionController::RoutingError, "No API reference" unless SOURCE.exist?

    expires_in CACHE_AGE, public: true
    # The HTML and the markdown share one URL, so a cache must key on Accept.
    response.headers["Vary"] = "Accept"
    response.headers["Link"] = %(<#{api_docs_url(format: :md)}>; rel="alternate"; type="text/markdown")

    return render(plain: SOURCE.read, content_type: "text/markdown") if markdown_requested?

    document  = self.class.render_markdown(SOURCE.read)
    # Safe to mark: the source is a file in this repository, not user input, and
    # the renderer is configured with escape_html so any HTML inside the
    # markdown comes out escaped. Saying so here keeps the reasoning next to the
    # renderer rather than leaving a bare raw() in the template.
    @body     = document[:html].html_safe # rubocop:disable Rails/OutputSafety
    @headings = document[:headings]

    # A client that asks for neither format still gets the page.
    render formats: :html
  end

  # @return [Hash] the rendered HTML and the top-level headings, for the menu.
  def self.render_markdown(text)
    html = markdown.render(text)
    doc  = Nokogiri::HTML.fragment(html)

    headings = doc.css("h2").filter_map do |node|
      { id: node["id"], text: node.text } if node["id"].present?
    end

    { html: doc.to_html, headings: headings }
  end

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

  def markdown_requested?
    case params[:format]
    when "md"   then true
    when "html" then false
    when nil    then prefers_markdown?
    else raise ActionController::UnknownFormat
    end
  end

  # Rails ignores an Accept header that also lists */*, and most agents send
  # one, for example "text/markdown, text/html, */*". This method reads the
  # header itself. Markdown wins only when the client ranks it above HTML.
  def prefers_markdown?
    types = Mime::Type.parse(request.headers["Accept"].to_s)
    types.find { |type| type == Mime[:md] || type == Mime[:html] } == Mime[:md]
  rescue Mime::Type::InvalidMimeType
    false
  end
end
