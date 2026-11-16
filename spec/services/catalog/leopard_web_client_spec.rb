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

  let(:search_url) { Catalog::LeopardWebClient::BASE_URL }

  # Banner answers this one only over POST, with the term and the CRN in a
  # form body. The bug was in the request, not in the parsing.
  def stub_enrollment(body: ENROLLMENT_HTML, status: 200, crn: "16160")
    stub_request(:post, "#{search_url}getEnrollmentInfo")
      .with(body: { "term" => "202710", "courseReferenceNumber" => crn })
      .to_return(status: status, body: body, headers: { "Content-Type" => "text/html" })
  end

  describe "#get_enrollment_info" do
    let(:service) { described_class.new(term: 202710, course_reference_number: 16_160) }

    it "sends the term and the crn, which Banner needs to pick a section" do
      request = stub_enrollment

      service.get_enrollment_info

      expect(request).to have_been_requested.once
    end

    it "returns the enrollment and waitlist numbers" do
      stub_enrollment

      result = service.get_enrollment_info

      expect(result[:enrollment]).to eq(actual: 15, maximum: 16, seats_available: 1)
      expect(result[:waitlist]).to eq(capacity: 0, actual: 0, seats_available: 0)
    end

    it "keeps the negative count of an over-enrolled section, as the importer does" do
      stub_enrollment(body: OVER_ENROLLED_HTML, crn: "16962")

      result = described_class.new(term: 202710, course_reference_number: 16_962).get_enrollment_info

      expect(result[:enrollment]).to eq(actual: 23, maximum: 15, seats_available: -8)
      expect(result[:waitlist][:seats_available]).to eq(-2)
    end

    it "returns nil when the page carries no enrollment section" do
      stub_enrollment(body: EMPTY_HTML)

      expect(service.get_enrollment_info).to be_nil
    end

    it "refuses to ask without a term" do
      service = described_class.new(course_reference_number: 16_160)

      expect { service.get_enrollment_info }.to raise_error(ArgumentError, /term is required/)
    end

    it "refuses to ask without a crn" do
      service = described_class.new(term: 202710)

      expect { service.get_enrollment_info }.to raise_error(ArgumentError, /course_reference_number is required/)
    end
  end

  describe "#get_class_details" do
    let(:service) { described_class.new(term: 202710, course_reference_number: 16_004) }
    let(:query)   { { "term" => "202710", "courseReferenceNumber" => "16004" } }
    let(:details_html) do
      '<section aria-labelledby="classDetails"><span id="courseTitle">Calculus 2A</span></section>'
    end

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

    def stub_details(status: 200, body: details_html)
      stub_request(:get, "#{search_url}getClassDetails").with(query: query)
        .to_return(status: status, body: body, headers: { "Content-Type" => "text/html" })
    end

    def stub_meeting_times(status: 200, body: fmt_payload)
      stub_request(:get, "#{search_url}getFacultyMeetingTimes").with(query: query)
        .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    def stub_seats(status: 200)
      stub_enrollment(status: status, crn: "16004")
    end

    describe "faculty" do
      before do
        stub_details
        stub_seats
      end

      it "keeps the instructor Banner reports alongside the meeting times" do
        stub_meeting_times

        expect(service.get_class_details[:faculty]).to eq([
          {
            "displayName"      => "Elijah Sanderson",
            "emailAddress"     => "sandersone1@wit.edu",
            "primaryIndicator" => true
          }
        ])
      end

      it "drops an entry with no email, which no faculty record can match" do
        fmt_payload["fmt"].first["faculty"] << { "displayName" => "Staff", "emailAddress" => "" }
        stub_meeting_times

        expect(service.get_class_details[:faculty].size).to eq(1)
      end

      it "lists an instructor once when several meetings share them" do
        fmt_payload["fmt"] << fmt_payload["fmt"].first.deep_dup
        stub_meeting_times

        expect(service.get_class_details[:faculty].size).to eq(1)
      end

      it "defaults primaryIndicator to false when Banner omits it" do
        fmt_payload["fmt"].first["faculty"].first.delete("primaryIndicator")
        stub_meeting_times

        expect(service.get_class_details[:faculty].first["primaryIndicator"]).to be(false)
      end
    end

    it "sends the details, meeting times, and enrollment requests at the same time" do
      # Each answer waits until all three requests have arrived, so requests
      # sent one at a time never get past the first.
      arrived = Concurrent::CountDownLatch.new(3)
      together = lambda do |response|
        lambda do |_request|
          arrived.count_down
          raise "requests ran one at a time" unless arrived.wait(5)

          response
        end
      end
      stub_request(:get, "#{search_url}getClassDetails").with(query: query)
        .to_return(&together.call(status: 200, body: details_html))
      stub_request(:get, "#{search_url}getFacultyMeetingTimes").with(query: query)
        .to_return(&together.call(status: 200, body: "{}", headers: { "Content-Type" => "application/json" }))
      stub_request(:post, "#{search_url}getEnrollmentInfo")
        .to_return(&together.call(status: 200, body: ENROLLMENT_HTML))

      expect(service.get_class_details).to include(title: "Calculus 2A", seats_available: 1, seats_capacity: 16,
                                                   waitlist_capacity: 0, waitlist_available: 0)
    end

    it "still raises a meeting times failure for a section that exists" do
      stub_details
      stub_meeting_times(status: 400, body: {})
      stub_seats

      expect { service.get_class_details }.to raise_error(Catalog::LeopardWebClient::RequestError, /status 400/)
    end

    it "returns nil for a missing section, even when the other requests fail" do
      stub_details(body: "<html><body></body></html>")
      stub_meeting_times(status: 400, body: {})
      stub_seats(status: 400)

      expect(service.get_class_details).to be_nil
    end

    it "lets a Banner cooldown in the enrollment request stop the caller" do
      stub_details
      stub_meeting_times
      stub_request(:post, "#{search_url}getEnrollmentInfo").to_raise(Catalog::BannerThrottle::CooldownError.new(60))

      expect { service.get_class_details }.to raise_error(Catalog::BannerThrottle::CooldownError)
    end

    it "keeps the details when only the enrollment request fails" do
      stub_details
      stub_meeting_times
      stub_seats(status: 400)

      details = service.get_class_details

      expect(details).to include(title: "Calculus 2A", faculty: be_present)
      expect(details).not_to have_key(:seats_available)
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

      expect(described_class.get_active_terms).to eq([ { code: "202710", description: "Fall 2026" } ])
      expect(stub).to have_been_requested.once
    end

    it "never reads the Hash that the old key held" do
      Rails.cache.write("leopard_web/active_terms", { success: true, terms: [] })
      stub_request(:get, terms_url).to_return(status: 200, body: [ { code: "202710", description: "Fall 2026" } ].to_json)

      expect(described_class.get_active_terms).to eq([ { code: "202710", description: "Fall 2026" } ])
    end

    it "raises and keeps nothing when Banner fails" do
      stub = stub_request(:get, terms_url).to_return(status: 400, body: "")

      2.times do
        expect { described_class.get_active_terms }.to raise_error(Catalog::LeopardWebClient::RequestError)
      end

      expect(stub).to have_been_requested.twice
    end
  end

  describe ".get_subjects" do
    it "returns the code and description of each subject in the term" do
      stub_request(:get, %r{\Ahttps://selfservice\.wit\.edu/StudentRegistrationSsb/ssb/classSearch/get_subject})
        .with(query: hash_including("term" => "202710", "max" => "500"))
        .to_return(status: 200, body: file_fixture("leopard_web/subjects.json").read,
                   headers: { "Content-Type" => "application/json" })

      expect(described_class.get_subjects(term: 202710))
        .to include({ code: "CRES", description: "Climate Resilience" }, { code: "COMP", description: "Computer Science (COMP)" })
    end

    # getClassDetails gives "&", so the lookup by label needs it too.
    it "decodes the HTML entities in a description" do
      stub_request(:get, %r{classSearch/get_subject})
        .to_return(status: 200, body: file_fixture("leopard_web/subjects.json").read,
                   headers: { "Content-Type" => "application/json" })

      expect(described_class.get_subjects(term: 202710)).to include({ code: "EPIC", description: "EPIC Themes in Hum & Soc Sci" })
    end

    it "raises on a failed request" do
      stub_request(:get, %r{classSearch/get_subject}).to_return(status: 400, body: "")

      expect { described_class.get_subjects(term: 202710) }.to raise_error(described_class::RequestError)
    end
  end

  describe "Banner errors" do
    let(:url) { "#{described_class::BASE_URL}getFacultyMeetingTimes" }

    it "retries a 500 and returns the next answer (Catalog::BannerThrottle)" do
      stub = stub_request(:get, url).with(query: hash_including("term" => "202720"))
                                    .to_return({ status: 500 },
                                               { status: 200, body: { fmt: [] }.to_json,
                                                 headers: { "Content-Type" => "application/json" } })

      result = described_class.new(term: 202720, course_reference_number: 20382).get_faculty_meeting_times

      expect(result).to eq("fmt" => [])
      expect(stub).to have_been_requested.twice
    end

    it "raises a RequestError at once while Banner cools down" do
      stub = stub_request(:get, url).with(query: hash_including({}))
      Catalog::BannerThrottle::COOLDOWN_AFTER.times { Catalog::BannerThrottle.record_failure }

      expect { described_class.new(term: 202720, course_reference_number: 20382).get_faculty_meeting_times }
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
