# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeopardWebService, type: :service do
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
  # its cap. The courses table forbids a negative count.
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

    it "reports no seat left for an over-enrolled section, not a negative count" do
      service = described_class.new(action: :get_enrollment_info, term: 202710,
                                    course_reference_number: 16_962)
      stub_connection(service, body: OVER_ENROLLED_HTML)

      result = service.call

      expect(result[:enrollment]).to eq(actual: 23, maximum: 15, seats_available: 0)
      expect(result[:waitlist][:seats_available]).to eq(0)
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
end
