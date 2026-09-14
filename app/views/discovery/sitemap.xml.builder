# frozen_string_literal: true

xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  DiscoveryController::WEBSITE_PATHS.each do |path|
    xml.url do
      xml.loc URI.join(root_url, path).to_s
    end
  end

  xml.url do
    xml.loc api_docs_url
  end
end
