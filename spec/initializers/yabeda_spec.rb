# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Prometheus exporter" do
  def scrape
    app = Yabeda::Prometheus::Exporter.rack_app(use_deflater: false)
    status, headers, body = app.call(Rack::MockRequest.env_for("/metrics"))
    text = +""
    body.each { |chunk| text << chunk }
    [ status, headers, text ]
  end

  it "serves the app and job metrics in the Prometheus text format" do
    create(:user)

    status, headers, text = scrape

    expect(status).to eq(200)
    expect(headers["content-type"]).to start_with("text/plain")
    expect(text).to include("# TYPE calendar_extension_events_total counter")
    expect(text).to match(/^calendar_users \d+/)
    expect(text).to include("# TYPE activejob_executed_total counter")
  end

  # Specs use the in-memory store, but production uses the file store, which
  # reads the labels back from the files. Ruby 4.0 removed CGI.parse, which
  # that read needs.
  it "renders labeled values from the file store that production uses" do
    original = Prometheus::Client.config.data_store

    Dir.mktmpdir do |dir|
      Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(dir: dir)
      registry = Prometheus::Client::Registry.new
      counter  = registry.counter(:spec_events_total, docstring: "Spec events", labels: %i[event])
      counter.increment(labels: { event: "calendar_link_copied" })

      expect(Prometheus::Client::Formats::Text.marshal(registry))
        .to include('spec_events_total{event="calendar_link_copied"} 1.0')
    end
  ensure
    Prometheus::Client.config.data_store = original
  end

  it "answers nothing but the metrics path" do
    app = Yabeda::Prometheus::Exporter.rack_app(use_deflater: false)
    status, _headers, _body = app.call(Rack::MockRequest.env_for("/admin"))

    expect(status).to eq(404)
  end
end
