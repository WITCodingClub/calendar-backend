# frozen_string_literal: true

require "rails_helper"

# Production has one Postgres server. A Blazer query with no time limit can
# take the CPU and I/O that the app needs.
RSpec.describe "config/blazer.yml" do
  let(:data_source) { Blazer.data_sources.fetch("main") }

  it "sets a statement timeout of 15 seconds" do
    expect(data_source.timeout).to eq(15)
  end

  it "applies the timeout to each query" do
    result = data_source.run_statement("SHOW statement_timeout")

    expect(result.error).to be_nil
    expect(result.rows).to eq([ [ "15s" ] ])
  end
end
