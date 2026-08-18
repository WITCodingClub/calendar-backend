# frozen_string_literal: true

# Publishes the public catalog API reference at /docs/api.
#
# The page renders docs/public-catalog-api.md, the same file the repository
# keeps, so the site and the repository cannot say different things.
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

    document  = self.class.render_markdown(SOURCE.read)
    @body     = document[:html]
    @headings = document[:headings]

    expires_in CACHE_AGE, public: true
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
end
