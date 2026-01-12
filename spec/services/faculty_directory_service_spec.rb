# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe FacultyDirectoryService, type: :service do
  describe ".call" do
    context "when fetching a single page successfully" do
      let(:mock_html) do
        <<~HTML
          <html>
            <body>
              <div class="result-count">Showing 1 - 12 of 809 results</div>
              <div class="views-row">
                <img src="/photos/smith.jpg">
                <h2 class="name">John Smith</h2>
                <div class="title">Professor, Computer Science</div>
                <a href="mailto:smithj@wit.edu">smithj@wit.edu</a>
                <div class="phone">617-989-1234</div>
                <div class="office">Beatty Hall - 301</div>
                <div class="department">Computer Science</div>
                <div class="school">School of Computing & Data Science</div>
              </div>
            </body>
          </html>
        HTML
      end

      before do
        stub_request(:get, "https://wit.edu/faculty-staff-directory")
          .with(query: hash_including("page" => "0"))
          .to_return(status: 200, body: mock_html)
      end

      it "parses faculty data correctly" do
        result = described_class.new(page: 0, fetch_all: false).call

        expect(result[:success]).to be true
        expect(result[:total_count]).to eq(809)
        expect(result[:faculty].length).to eq(1)

        faculty = result[:faculty].first
        expect(faculty[:display_name]).to eq("John Smith")
        expect(faculty[:email]).to eq("smithj@wit.edu")
        expect(faculty[:title]).to eq("Professor, Computer Science")
        expect(faculty[:phone]).to eq("617-989-1234")
        expect(faculty[:office_location]).to include("Beatty")
      end
    end

    context "when searching by name" do
      let(:mock_html) do
        <<~HTML
          <html>
            <body>
              <div class="result-count">Showing 1 - 2 of 2 results</div>
              <div class="views-row">
                <h2>Mami Wentworth</h2>
                <div class="title">Associate Professor</div>
                <a href="mailto:wentworthm1@wit.edu">wentworthm1@wit.edu</a>
              </div>
            </body>
          </html>
        HTML
      end

      before do
        stub_request(:get, "https://wit.edu/faculty-staff-directory")
          .with(query: hash_including("search" => "Mami"))
          .to_return(status: 200, body: mock_html)
      end

      it "returns search results" do
        result = described_class.new(search: "Mami", fetch_all: false).call

        expect(result[:success]).to be true
        expect(result[:faculty].length).to eq(1)
        expect(result[:faculty].first[:email]).to eq("wentworthm1@wit.edu")
      end
    end

    context "when request fails" do
      before do
        stub_request(:get, "https://wit.edu/faculty-staff-directory")
          .with(query: hash_including("page" => "0"))
          .to_return(status: 500, body: "Server Error")
      end

      it "returns error result" do
        result = described_class.new(page: 0, fetch_all: false).call

        expect(result[:success]).to be false
        expect(result[:error]).to include("HTTP 500")
        expect(result[:faculty]).to eq([])
      end
    end

    context "when fetching all pages" do
      let(:page1_html) do
        <<~HTML
          <html>
            <body>
              <div class="result-count">Showing 1 - 2 of 3 results</div>
              <div class="views-row">
                <h2>John Smith</h2>
                <a href="mailto:smithj@wit.edu">smithj@wit.edu</a>
              </div>
              <div class="views-row">
                <h2>Jane Doe</h2>
                <a href="mailto:doej@wit.edu">doej@wit.edu</a>
              </div>
            </body>
          </html>
        HTML
      end

      let(:page2_html) do
        <<~HTML
          <html>
            <body>
              <div class="result-count">Showing 3 - 3 of 3 results</div>
              <div class="views-row">
                <h2>Bob Jones</h2>
                <a href="mailto:jonesb@wit.edu">jonesb@wit.edu</a>
              </div>
            </body>
          </html>
        HTML
      end

      before do
        stub_request(:get, "https://wit.edu/faculty-staff-directory")
          .with(query: hash_including("page" => "0"))
          .to_return(status: 200, body: page1_html)

        stub_request(:get, "https://wit.edu/faculty-staff-directory")
          .with(query: hash_including("page" => "1"))
          .to_return(status: 200, body: page2_html)

        # Disable caching for this test
        allow(Rails.cache).to receive(:fetch).and_yield
      end

      it "fetches all pages and combines results" do
        result = described_class.call

        expect(result[:success]).to be true
        expect(result[:total_count]).to eq(3)
        expect(result[:faculty].length).to eq(3)
        expect(result[:faculty].pluck(:email)).to contain_exactly(
          "smithj@wit.edu", "doej@wit.edu", "jonesb@wit.edu"
        )
      end
    end
  end
end
