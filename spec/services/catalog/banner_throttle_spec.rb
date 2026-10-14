# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::BannerThrottle do
  include ActiveSupport::Testing::TimeHelpers

  let(:base) { "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/" }
  let(:connection) do
    Faraday.new(url: base) do |f|
      f.request :url_encoded
      f.use described_class
      f.adapter Faraday.default_adapter
    end
  end

  def requests(outcome) = Yabeda.calendar.banner_requests_total.get(outcome: outcome) || 0

  describe "pacing" do
    it "lets a burst through, then makes each request wait its turn" do
      waits = Array.new(described_class::BURST) { described_class.acquire }
      expect(waits).to all(eq(0.0))

      wait = described_class.acquire
      expect(wait).to be_within(0.05).of(1 / described_class::RATE_PER_SECOND)
      expect(described_class).to have_received(:pause).with(wait)
    end
  end

  describe "retries" do
    it "retries a 500 and returns the answer that follows" do
      stub = stub_request(:get, "#{base}searchResults/getClassDetails")
             .to_return({ status: 500 }, { status: 200, body: "ok" })

      expect { connection.get("searchResults/getClassDetails") }
        .to change { requests(:retried) }.by(1).and change { requests(:ok) }.by(1)
      expect(stub).to have_been_requested.twice
    end

    it "waits the Retry-After seconds Banner asks for, inside a job" do
      stub_request(:get, "#{base}x").to_return({ status: 429, headers: { "Retry-After" => "7" } }, { status: 200 })

      ActiveSupport::ExecutionContext.set(job: Object.new) { connection.get("x") }

      expect(described_class).to have_received(:pause).with(7)
    end

    it "does not make a web request wait longer than its budget" do
      stub = stub_request(:get, "#{base}x").to_return(status: 429, headers: { "Retry-After" => "7" })

      expect(connection.get("x").status).to eq(429)
      expect(stub).to have_been_requested.once
    end

    it "retries a connection failure" do
      stub_request(:get, "#{base}x").to_raise(Faraday::ConnectionFailed.new("reset")).then.to_return(status: 200)

      expect(connection.get("x").status).to eq(200)
    end

    it "gives up after the web request budget and returns the last answer" do
      stub = stub_request(:get, "#{base}x").to_return(status: 503)

      expect { expect(connection.get("x").status).to eq(503) }.to change { requests(:failed) }.by(1)
      expect(stub).to have_been_requested.times(described_class::BUDGETS[:request].retries + 1)
    end

    it "gives a job a larger budget" do
      stub = stub_request(:get, "#{base}x").to_return(status: 503)

      ActiveSupport::ExecutionContext.set(job: Object.new) { connection.get("x") }

      # The cooldown opens before the job budget runs out.
      expect(stub).to have_been_requested.times(described_class::COOLDOWN_AFTER)
    end

    it "does not retry a 4xx answer" do
      stub = stub_request(:get, "#{base}x").to_return(status: 400)

      expect(connection.get("x").status).to eq(400)
      expect(stub).to have_been_requested.once
    end

    it "retries the POSTs that only read, and no other POST" do
      enrollment = stub_request(:post, "#{base}searchResults/getEnrollmentInfo").to_return({ status: 500 }, { status: 200 })
      other      = stub_request(:post, "#{base}searchResults/other").to_return(status: 500)

      expect(connection.post("searchResults/getEnrollmentInfo", term: 1).status).to eq(200)
      expect(connection.post("searchResults/other", term: 1).status).to eq(500)
      expect(enrollment).to have_been_requested.twice
      expect(other).to have_been_requested.once
    end

    it "sends the same form body on a retry" do
      stub = stub_request(:post, "#{base}term/search").with(body: "term=202720")
                                                      .to_return({ status: 502 }, { status: 200 })

      connection.post("term/search", term: 202720)

      expect(stub).to have_been_requested.twice
    end
  end

  describe "cooldown" do
    it "opens after failures in a row, refuses requests at once, then closes" do
      stub = stub_request(:get, "#{base}x").to_return(status: 500)
      described_class::COOLDOWN_AFTER.times { described_class.record_failure }

      expect { connection.get("x") }
        .to raise_error(described_class::CooldownError) { |e| expect(e.retry_after).to be_between(1, 180) }
        .and change { requests(:cooldown) }.by(1)
      expect(stub).not_to have_been_requested
      expect(described_class::CooldownError.new(5)).to be_a(Catalog::LeopardWebClient::RequestError)

      allow(Process).to receive(:clock_gettime).and_wrap_original do |original, *args|
        original.call(*args) + described_class::COOLDOWN.to_i + 1
      end
      stub_request(:get, "#{base}x").to_return(status: 200)

      expect(connection.get("x").status).to eq(200)
    end

    it "starts the count again after a success" do
      (described_class::COOLDOWN_AFTER - 1).times { described_class.record_failure }
      described_class.record_success
      described_class.record_failure

      expect(described_class.cooldown_remaining).to be_nil
    end
  end

  describe ".current_budget" do
    it "is :request by default, :job inside a job, and what with_budget names" do
      expect(described_class.current_budget).to eq(:request)
      ActiveSupport::ExecutionContext.set(job: Object.new) { expect(described_class.current_budget).to eq(:job) }
      described_class.with_budget(:job) { expect(described_class.current_budget).to eq(:job) }
    end
  end
end
