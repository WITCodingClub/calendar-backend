# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::SeatRefresh do
  let(:base) { "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/" }
  let(:term) { create(:term, uid: 202720, season: :spring, year: 2027) }
  let!(:full)       { create(:course, term: term, crn: 20452, seats_capacity: 25, seats_available: 17) }
  let!(:unchanged)  { create(:course, term: term, crn: 20393, seats_capacity: 25, seats_available: 13, waitlist_capacity: 0, waitlist_available: 0) }
  let!(:over)       { create(:course, term: term, crn: 20500, seats_capacity: 15, seats_available: 2, waitlist_capacity: 0, waitlist_available: 0) }
  let!(:not_listed) { create(:course, term: term, crn: 20999, seats_capacity: 30, seats_available: 30) }

  before do
    stub_request(:post, "#{base}term/search").with(query: { mode: "search" })
      .to_return(status: 200, headers: { "Set-Cookie" => "JSESSIONID=abc; Path=/" })
  end

  def stub_search(body)
    stub_request(:get, %r{\A#{Regexp.escape(base)}searchResults/searchResults})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: body)
  end

  it "writes the counts that changed and returns how many" do
    stub_search(file_fixture("leopard_web/search_results_seats.json").read)

    expect(described_class.call(term)).to eq(2)
    expect(full.reload.slice(:seats_capacity, :seats_available)).to eq("seats_capacity" => 25, "seats_available" => 0)
  end

  it "writes the waitlist counts" do
    stub_search(file_fixture("leopard_web/search_results_seats.json").read)

    described_class.call(term)

    expect(full.reload).to have_attributes(waitlist_capacity: 5, waitlist_available: 1)
  end

  it "writes the waitlist counts when the seats did not change" do
    unchanged.update!(waitlist_capacity: 5, waitlist_available: 5)
    stub_search(file_fixture("leopard_web/search_results_seats.json").read)

    described_class.call(term)

    expect(unchanged.reload).to have_attributes(seats_available: 13, waitlist_capacity: 0, waitlist_available: 0)
  end

  # Banner reports a negative count for an over-enrolled section, as the import keeps it.
  it "keeps a negative count" do
    stub_search(file_fixture("leopard_web/search_results_seats.json").read)

    described_class.call(term)

    expect(over.reload.seats_available).to eq(-8)
  end

  it "leaves a section alone when its counts did not change or Banner does not list it" do
    stub_search(file_fixture("leopard_web/search_results_seats.json").read)

    expect { described_class.call(term) }.not_to(change { [ unchanged.reload.updated_at, not_listed.reload.updated_at ] })
    expect(not_listed.seats_available).to eq(30)
  end

  # Catalog::SectionSync can write newer counts while the search is in flight.
  it "leaves a section alone that changed during the fetch" do
    stub_search(file_fixture("leopard_web/search_results_seats.json").read)
    full.update_column(:updated_at, 1.minute.from_now) # rubocop:disable Rails/SkipsModelValidations

    described_class.call(term)

    expect(full.reload.seats_available).to eq(17)
  end

  # The database checks that seats_available is not more than seats_capacity.
  it "writes neither count when Banner sends only one" do
    stub_search({ totalCount: 1, data: [ { courseReferenceNumber: "20452", maximumEnrollment: nil, seatsAvailable: 0 } ] }.to_json)

    expect(described_class.call(term)).to eq(0)
    expect(full.reload).to have_attributes(seats_capacity: 25, seats_available: 17, waitlist_capacity: nil)
  end

  it "returns nil and writes nothing when Banner fails" do
    stub_request(:get, %r{searchResults/searchResults}).to_return(status: 404)

    capture_error_reports do
      expect(described_class.call(term)).to be_nil
    end
    expect(full.reload.seats_available).to eq(17)
  end
end
