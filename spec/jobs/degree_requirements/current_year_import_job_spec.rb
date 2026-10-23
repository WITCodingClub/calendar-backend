# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::CurrentYearImportJob do
  let(:url) { "https://catalog.wit.edu/programs-az/" }

  it "queues the import of the year the catalog site shows" do
    stub_request(:get, url).to_return(status: 200, body: "<footer>Boston, MA 2026-2027</footer>")

    expect { described_class.perform_now }.to have_enqueued_job(DegreeRequirements::ImportJob).with(2026)
  end

  it "raises when the site names no catalog year" do
    stub_request(:get, url).to_return(status: 200, body: "<p>Down for maintenance</p>")

    expect { described_class.perform_now }.to raise_error(DegreeRequirements::Error, /no catalog year/)
  end
end
