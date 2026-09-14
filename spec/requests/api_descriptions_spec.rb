# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API descriptions", type: :request do
  describe "GET /docs/api/openapi.json" do
    let(:document) { JSON.parse(response.body) }

    before { get "/docs/api/openapi.json", headers: { "User-Agent" => "curl/8.7.1" } }

    it "publishes an OpenAPI 3.1 document" do
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/vnd.oai.openapi+json")
      expect(document["openapi"]).to eq("3.1.0")
    end

    it "names this host as the server" do
      expect(document["servers"]).to eq([ { "url" => "http://example.com" } ])
    end

    it "describes every catalog route, and no path that has no route" do
      routes = Rails.application.routes.routes.filter_map do |route|
        path = route.path.spec.to_s.delete_suffix("(.:format)")
        path.gsub(/:(\w+)/, '{\1}') if path.start_with?("/api/v1/catalog/")
      end

      expect(document["paths"].keys).to match_array(routes.uniq)
    end

    it "gives every operation a unique operationId" do
      ids = document["paths"].values.flat_map(&:values).pluck("operationId")

      expect(ids).to all(be_present)
      expect(ids).to eq(ids.uniq)
    end

    it "resolves every reference" do
      refs = response.body.scan(%r{"\$ref":"#/components/(\w+)/(\w+)"}).uniq

      expect(refs).not_to be_empty
      refs.each do |(kind, name)|
        expect(document.dig("components", kind, name)).to be_present, "#/components/#{kind}/#{name} is missing"
      end
    end

    it "gives every 4xx and 5xx response the Error schema" do
      responses = document["paths"].values.flat_map(&:values).flat_map { |op| op["responses"].to_a }
      errors    = responses.select { |status, _| status.match?(/\A[45]\d\d\z/) }

      expect(errors).not_to be_empty
      errors.each do |status, ref|
        name   = ref["$ref"].to_s.split("/").last
        schema = document.dig("components", "responses", name, "content", "application/json", "schema", "$ref")
        expect(schema).to eq("#/components/schemas/Error"), "#{status} #{name} has no Error schema"
      end
    end

    it "lists every error code that the API sends" do
      expect(document.dig("components", "schemas", "Error", "properties", "code", "enum"))
        .to contain_exactly("INVALID_FILTER", "NOT_FOUND", "RATE_LIMITED", "INTERNAL_ERROR")
    end

    it "declares the rate limit headers on every success and on the 429" do
      document["paths"].values.flat_map(&:values).each do |op|
        expect(op.dig("responses", "200", "headers").keys).to include("RateLimit", "RateLimit-Policy")
      end
      expect(document.dig("components", "responses", "TooManyRequests", "headers").keys)
        .to include("Retry-After", "RateLimit", "RateLimit-Policy")
    end

    it "states the deprecation policy" do
      expect(document.dig("info", "description")).to include("Deprecation", "Sunset", "90 days")
    end

    it "lets a proxy cache the file" do
      expect(response.headers["Cache-Control"]).to include("public")
    end
  end

  describe "GET /docs/api/schema.graphql" do
    it "publishes the schema that the endpoint runs" do
      get "/docs/api/schema.graphql", headers: { "User-Agent" => "curl/8.7.1" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/plain")
      expect(response.body).to eq(CatalogSchema.to_definition)
      expect(response.headers["Cache-Control"]).to include("public")
    end
  end
end
