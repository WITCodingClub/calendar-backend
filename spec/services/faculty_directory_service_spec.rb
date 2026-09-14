# frozen_string_literal: true

require "rails_helper"

RSpec.describe FacultyDirectoryService, type: :service do
  let(:base_url) { FacultyDirectoryService::BASE_URL }

  def stub_page(page:, fixture:, status: 200, employee_type: "All")
    stub_request(:get, base_url)
      .with(query: hash_including("page" => page.to_s, "employee_type" => employee_type))
      .to_return(status: status, body: file_fixture("faculty_directory/#{fixture}").read,
                 headers: { "Content-Type" => "text/html" })
  end

  describe "#call" do
    it "fetches a single page when a page number is given" do
      stub_page(page: 0, fixture: "page_single.html")

      result = described_class.new(page: 0, fetch_all: false).call

      expect(result[:success]).to be(true)
      expect(result[:total_count]).to eq(1)
      faculty = result[:faculty].first
      expect(faculty[:display_name]).to eq("Ada Byron")
      expect(faculty[:title]).to eq("Professor of Computer Science")
      expect(faculty[:email]).to eq("byrona@wit.edu")
      expect(faculty[:phone]).to eq("617-555-0100")
      expect(faculty[:office_location]).to eq("Beatty Hall - 205")
      expect(faculty[:department]).to eq("Computer Science Department")
      expect(faculty[:photo_url]).to eq("https://wit.edu/sites/default/files/2024-01/byron.jpg")
      expect(faculty[:profile_url]).to eq("https://wit.edu/directory/ada-byron")
    end

    it "skips cards with no email address" do
      stub_page(page: 0, fixture: "page_no_email.html")

      result = described_class.new(page: 0, fetch_all: false).call

      expect(result[:success]).to be(true)
      expect(result[:faculty]).to eq([])
    end

    it "returns an empty faculty list when there are no results" do
      stub_page(page: 0, fixture: "page_empty.html")

      result = described_class.new(page: 0, fetch_all: false).call

      expect(result).to eq(success: true, faculty: [], total_count: 0)
    end

    it "walks every page until it has collected the whole directory" do
      stub_page(page: 0, fixture: "pagination_page0.html")
      stub_page(page: 1, fixture: "pagination_page1.html")
      service = described_class.new
      allow(service).to receive(:sleep)

      result = service.call

      expect(result[:success]).to be(true)
      expect(result[:total_count]).to eq(2)
      expect(result[:faculty].map { |f| f[:email] }).to eq(%w[byrona@wit.edu hopperfieldg@wit.edu])
      expect(service).to have_received(:sleep).once
    end

    it "reports a failure without raising when the server answers with an error status" do
      stub_page(page: 0, fixture: "page_single.html", status: 500)

      result = described_class.new(page: 0, fetch_all: false).call

      expect(result).to eq(success: false, error: "HTTP 500", faculty: [], total_count: 0)
    end

    it "does not raise on a malformed HTML body, it just finds nothing" do
      stub_request(:get, base_url)
        .with(query: hash_including("page" => "0"))
        .to_return(status: 200, body: "<<<not really html>>>", headers: { "Content-Type" => "text/html" })

      result = described_class.new(page: 0, fetch_all: false).call

      expect(result[:success]).to be(true)
      expect(result[:faculty]).to eq([])
    end

    it "reports a failure without raising when the request times out" do
      stub_request(:get, base_url)
        .with(query: hash_including("page" => "0"))
        .to_timeout

      result = described_class.new(page: 0, fetch_all: false).call

      expect(result[:success]).to be(false)
      expect(result[:faculty]).to eq([])
      expect(result[:total_count]).to eq(0)
    end

    it "passes the search term through as a query parameter" do
      stub_request(:get, base_url)
        .with(query: hash_including("page" => "0", "search" => "Byron"))
        .to_return(status: 200, body: file_fixture("faculty_directory/page_single.html").read,
                   headers: { "Content-Type" => "text/html" })

      result = described_class.new(page: 0, fetch_all: false, search: "Byron").call

      expect(result[:success]).to be(true)
      expect(result[:faculty].first[:email]).to eq("byrona@wit.edu")
    end
  end

  describe "#call!" do
    it "returns the result when the fetch succeeds" do
      stub_page(page: 0, fixture: "page_single.html")

      result = described_class.new(page: 0, fetch_all: false).call!

      expect(result[:success]).to be(true)
    end

    it "raises with the underlying error message when the fetch fails" do
      stub_page(page: 0, fixture: "page_single.html", status: 503)

      expect { described_class.new(page: 0, fetch_all: false).call! }.to raise_error("HTTP 503")
    end
  end
end
