# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::LeopardWebClient, type: :service do
  # A trimmed copy of the section Banner returns for getEnrollmentInfo.
  ENROLLMENT_HTML = <<~HTML
    <section aria-labelledby="enrollmentInfo">
      <span class="status-bold">Enrollment Actual:</span> <span dir="ltr">15</span><br>
      <span class="status-bold">Enrollment Maximum:</span> <span dir="ltr">16</span><br>
      <span class="status-bold">Enrollment Seats Available:</span> <span dir="ltr">1</span><br>
      <span class="status-bold">Waitlist Capacity:</span> <span dir="ltr">0</span><br>
      <span class="status-bold">Waitlist Actual:</span> <span dir="ltr">0</span><br>
      <span class="status-bold">Waitlist Seats Available:</span> <span dir="ltr">0</span><br>
    </section>
  HTML

  # Banner reports a negative count for a section that holds more students than
  # its cap. The importer stores that number as is, so this client does too.
  OVER_ENROLLED_HTML = <<~HTML
    <section aria-labelledby="enrollmentInfo">
      <span class="status-bold">Enrollment Actual:</span> <span dir="ltr">23</span><br>
      <span class="status-bold">Enrollment Maximum:</span> <span dir="ltr">15</span><br>
      <span class="status-bold">Enrollment Seats Available:</span> <span dir="ltr">-8</span><br>
      <span class="status-bold">Waitlist Capacity:</span> <span dir="ltr">0</span><br>
      <span class="status-bold">Waitlist Actual:</span> <span dir="ltr">2</span><br>
      <span class="status-bold">Waitlist Seats Available:</span> <span dir="ltr">-2</span><br>
    </section>
  HTML

  # Banner answers with a page that has no enrollment section when it is not
  # told which section to describe.
  EMPTY_HTML = "<html><body><section aria-labelledby='other'></section></body></html>"

  describe "#get_enrollment_info" do
    # Records what the service actually sent, because the bug was in the
    # request, not in the parsing.
    def stub_connection(service, body:, status: 200)
      requests = []

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("getEnrollmentInfo") do |env|
          # Copy the request now. Faraday reuses the env and overwrites body
          # with the response, so holding the env itself proves nothing.
          requests << { method: env.method, body: env.request_body.to_s }
          [ status, { "Content-Type" => "text/html" }, body ]
        end
      end

      # Mirrors the real connection, which form-encodes the body.
      connection = Faraday.new do |f|
        f.request :url_encoded
        f.adapter :test, stubs
      end
      allow(service).to receive(:connection).and_return(connection)

      requests
    end

    it "sends the term and the crn, which Banner needs to pick a section" do
      service  = described_class.new(action: :get_enrollment_info, term: 202710,
                                     course_reference_number: 16_160)
      requests = stub_connection(service, body: ENROLLMENT_HTML)

      service.call

      expect(requests.size).to eq(1)
      expect(requests.first[:method]).to eq(:post)
      expect(requests.first[:body]).to include("term=202710")
      expect(requests.first[:body]).to include("courseReferenceNumber=16160")
    end

    it "returns the enrollment and waitlist numbers" do
      service = described_class.new(action: :get_enrollment_info, term: 202710,
                                    course_reference_number: 16_160)
      stub_connection(service, body: ENROLLMENT_HTML)

      result = service.call

      expect(result[:enrollment]).to eq(actual: 15, maximum: 16, seats_available: 1)
      expect(result[:waitlist]).to eq(capacity: 0, actual: 0, seats_available: 0)
    end

    it "keeps the negative count of an over-enrolled section, as the importer does" do
      service = described_class.new(action: :get_enrollment_info, term: 202710,
                                    course_reference_number: 16_962)
      stub_connection(service, body: OVER_ENROLLED_HTML)

      result = service.call

      expect(result[:enrollment]).to eq(actual: 23, maximum: 15, seats_available: -8)
      expect(result[:waitlist][:seats_available]).to eq(-2)
    end

    it "returns nil when the page carries no enrollment section" do
      service = described_class.new(action: :get_enrollment_info, term: 202710,
                                    course_reference_number: 16_160)
      stub_connection(service, body: EMPTY_HTML)

      expect(service.call).to be_nil
    end

    it "refuses to ask without a term" do
      service = described_class.new(action: :get_enrollment_info, course_reference_number: 16_160)

      expect { service.call }.to raise_error(ArgumentError, /term is required/)
    end

    it "refuses to ask without a crn" do
      service = described_class.new(action: :get_enrollment_info, term: 202710)

      expect { service.call }.to raise_error(ArgumentError, /course_reference_number is required/)
    end
  end

  describe ".get_enrollment_info" do
    it "passes the term and the crn through to the instance" do
      expect(described_class).to receive(:new).with(
        action: :get_enrollment_info, term: 202710, course_reference_number: 16_160
      ).and_return(instance_double(described_class, call: nil))

      described_class.get_enrollment_info(term: 202710, course_reference_number: 16_160)
    end
  end

  describe "#get_class_details faculty" do
    # A trimmed copy of what Banner returns for CRN 16004 in term 202710. The
    # faculty array sits beside meetingTime in the same fmt entry, and the
    # service used to read only the meeting time.
    let(:fmt_payload) do
      {
        "fmt" => [
          {
            "courseReferenceNumber" => "16004",
            "faculty" => [
              {
                "displayName"      => "Elijah Sanderson",
                "emailAddress"     => "sandersone1@wit.edu",
                "primaryIndicator" => true
              }
            ],
            "meetingTime" => {
              "beginTime" => "1300", "endTime" => "1410",
              "building" => "BEATT", "buildingDescription" => "Beatty Hall",
              "room" => "420", "startDate" => "09/08/2026", "endDate" => "10/20/2026",
              "monday" => true, "wednesday" => true, "friday" => true,
              "tuesday" => false, "thursday" => false, "saturday" => false, "sunday" => false
            }
          }
        ]
      }
    end

    def service_with(fmt)
      service = described_class.new(action: :get_class_details, term: 202710,
                                    course_reference_number: 16_004)
      allow(service).to receive(:handle_response).and_return({ title: "Calculus 2A" })
      allow(service).to receive(:get_faculty_meeting_times).and_return(fmt)
      allow(service).to receive(:get_enrollment_info).and_return(nil)
      allow(service).to receive(:connection).and_return(instance_double(Faraday::Connection, get: nil))
      service
    end

    it "keeps the instructor Banner reports alongside the meeting times" do
      details = service_with(fmt_payload).call

      expect(details[:faculty]).to eq([
        {
          "displayName"      => "Elijah Sanderson",
          "emailAddress"     => "sandersone1@wit.edu",
          "primaryIndicator" => true
        }
      ])
    end

    it "drops an entry with no email, which no faculty record can match" do
      fmt_payload["fmt"].first["faculty"] << { "displayName" => "Staff", "emailAddress" => "" }

      expect(service_with(fmt_payload).call[:faculty].size).to eq(1)
    end

    it "lists an instructor once when several meetings share them" do
      fmt_payload["fmt"] << fmt_payload["fmt"].first.deep_dup

      expect(service_with(fmt_payload).call[:faculty].size).to eq(1)
    end

    it "defaults primaryIndicator to false when Banner omits it" do
      fmt_payload["fmt"].first["faculty"].first.delete("primaryIndicator")

      expect(service_with(fmt_payload).call[:faculty].first["primaryIndicator"]).to be(false)
    end
  end

  describe "#get_class_details requests" do
    let(:service) do
      described_class.new(action: :get_class_details, term: 202710, course_reference_number: 16_004)
    end

    let(:connection) { instance_double(Faraday::Connection, get: nil) }

    before do
      allow(service).to receive(:connection).and_return(connection)
      allow(service).to receive(:handle_response).and_return({ title: "Calculus 2A" })
    end

    it "sends the details, meeting times, and enrollment requests at the same time" do
      in_flight = Queue.new
      wait_for_all = lambda do |name, result|
        in_flight << name
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        sleep 0.01 while in_flight.size < 3 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        raise "requests ran one at a time" if in_flight.size < 3

        result
      end
      allow(connection).to receive(:get) { wait_for_all.call(:details, nil) }
      allow(service).to receive(:get_faculty_meeting_times) { wait_for_all.call(:fmt, nil) }
      allow(service).to receive(:get_enrollment_info) do
        wait_for_all.call(:enrollment, { enrollment: { seats_available: 4, maximum: 30 }, waitlist: { capacity: 5, seats_available: 2 } })
      end

      details = service.call

      expect(details).to include(title: "Calculus 2A", seats_available: 4, seats_capacity: 30,
                                 waitlist_capacity: 5, waitlist_available: 2)
    end

    it "still raises a meeting times failure for a section that exists" do
      allow(service).to receive(:get_faculty_meeting_times).and_raise(Catalog::LeopardWebClient::RequestError, "Banner is down")
      allow(service).to receive(:get_enrollment_info).and_return(nil)

      expect { service.call }.to raise_error(Catalog::LeopardWebClient::RequestError, "Banner is down")
    end

    it "returns nil for a missing section, even when the other requests fail" do
      allow(service).to receive(:handle_response).and_return(nil)
      allow(service).to receive(:get_faculty_meeting_times).and_raise(Catalog::LeopardWebClient::RequestError, "Banner is down")
      allow(service).to receive(:get_enrollment_info).and_raise(Catalog::LeopardWebClient::RequestError, "Banner is down")

      expect(service.call).to be_nil
    end

    it "keeps the details when only the enrollment request fails" do
      allow(service).to receive(:get_faculty_meeting_times).and_return(nil)
      allow(service).to receive(:get_enrollment_info).and_raise(Catalog::LeopardWebClient::RequestError, "Banner is down")

      expect(service.call).to eq({ title: "Calculus 2A" })
    end
  end

  describe ".get_active_terms" do
    let(:terms_url) { %r{\Ahttps://selfservice\.wit\.edu/StudentRegistrationSsb/ssb/courseSearch/getTerms} }

    before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

    it "asks Banner once and keeps a good answer" do
      stub = stub_request(:get, terms_url)
             .to_return(status: 200, body: [ { code: "202710", description: "Fall 2026" } ].to_json,
                        headers: { "Content-Type" => "application/json" })

      2.times { described_class.get_active_terms }

      expect(described_class.get_active_terms[:success]).to be(true)
      expect(stub).to have_been_requested.once
    end

    it "does not keep a failed answer" do
      stub = stub_request(:get, terms_url).to_return(status: 400, body: "")

      2.times { described_class.get_active_terms }

      expect(stub).to have_been_requested.twice
    end
  end

  describe "Banner errors" do
    let(:url) { "#{described_class::BASE_URL}getFacultyMeetingTimes" }

    it "retries a 500 and returns the next answer (Catalog::BannerThrottle)" do
      stub = stub_request(:get, url).with(query: hash_including("term" => "202720"))
                                    .to_return({ status: 500 },
                                               { status: 200, body: { fmt: [] }.to_json,
                                                 headers: { "Content-Type" => "application/json" } })

      result = described_class.get_faculty_meeting_times(term: 202720, course_reference_number: 20382)

      expect(result).to eq("fmt" => [])
      expect(stub).to have_been_requested.twice
    end

    it "raises a RequestError at once while Banner cools down" do
      stub = stub_request(:get, url).with(query: hash_including({}))
      Catalog::BannerThrottle::COOLDOWN_AFTER.times { Catalog::BannerThrottle.record_failure }

      expect { described_class.get_faculty_meeting_times(term: 202720, course_reference_number: 20382) }
        .to raise_error(described_class::RequestError)
      expect(stub).not_to have_been_requested
    end
  end

  describe ".fetch_linked_sections" do
    let(:url) { "#{described_class::BASE_URL}fetchLinkedSections" }

    def stub_fixture(name)
      stub_request(:get, url).with(query: { term: "202720", courseReferenceNumber: "20452" })
                             .to_return(status: 200, body: file_fixture("leopard_web/#{name}").read,
                                        headers: { "Content-Type" => "application/json" })
    end

    def fetch = described_class.fetch_linked_sections(term: 202720, course_reference_number: 20452)

    it "returns each option group with Banner's credits" do
      stub_fixture("linked_sections_options.json")

      expect(fetch).to eq([
        [ { crn: 20455, credit_hours: 0 } ],
        [ { crn: 20456, credit_hours: 0 }, { crn: 20459, credit_hours: 0 } ]
      ])
    end

    it "returns no groups for a section with no partners" do
      stub_fixture("linked_sections_none.json")

      expect(fetch).to eq([])
    end

    it "raises on an error status" do
      stub_request(:get, url).with(query: hash_including({})).to_return(status: 500, body: "error")

      expect { fetch }.to raise_error(described_class::RequestError)
    end

    it "raises when the body has no linkedData" do
      stub_request(:get, url).with(query: hash_including({}))
                             .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      expect { fetch }.to raise_error(described_class::ParseError)
    end

    it "needs a term and a CRN" do
      expect { described_class.fetch_linked_sections(term: nil, course_reference_number: 1) }.to raise_error(ArgumentError)
      expect { described_class.fetch_linked_sections(term: 1, course_reference_number: nil) }.to raise_error(ArgumentError)
    end
  end
end
