# frozen_string_literal: true

# An RFC 9727 API catalog in the RFC 9264 linkset format. It lists the public
# catalog API only. The extension API needs a token, so agents cannot use it.
#
# Each anchor names one surface of the API. Each surface links to its own part
# of the reference, and to the markdown copy that agents read.
#
# The REST and CSV surfaces have no route of their own, so their anchors join a
# path to root_url. root_url and the other helpers share one host.
surfaces = {
  URI.join(root_url, "api/v1/catalog").to_s => "rest",
  api_graphql_url                           => "graphql",
  URI.join(root_url, "reports").to_s        => "csv-reports"
}

json.linkset surfaces do |anchor, heading|
  json.anchor anchor
  json.set! "service-doc", [
    { href: api_docs_url(anchor: heading), type: "text/html" },
    { href: api_docs_url(format: :md), type: "text/markdown" }
  ]
end
