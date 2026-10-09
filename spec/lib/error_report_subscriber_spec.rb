# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorReportSubscriber do
  def reported_count(**labels)
    Yabeda.calendar.errors_reported_total.get(**labels) || 0
  end

  let(:labels) { { error_class: "ArgumentError", handled: "true", severity: "warning", source: "spec.subscriber" } }

  it "is subscribed to Rails.error" do
    expect { Rails.error.report(ArgumentError.new("synthetic"), handled: true, source: "spec.subscriber") }
      .to change { reported_count(**labels) }.by(1)
  end

  it "counts an unhandled error with its own labels" do
    unhandled = labels.merge(handled: "false", severity: "error")

    expect { Rails.error.report(ArgumentError.new("synthetic"), handled: false, source: "spec.subscriber") }
      .to change { reported_count(**unhandled) }.by(1)
  end

  it "writes one JSON log line with the plain context values only" do
    allow(Rails.logger).to receive(:warn)

    Rails.error.report(ArgumentError.new("synthetic failure"), handled: true, source: "spec.subscriber",
                                                               context: { user_id: 42, job: Object.new })

    expect(Rails.logger).to have_received(:warn).once do |line|
      payload = JSON.parse(line)
      expect(payload).to include("message" => "error_reported", "error_class" => "ArgumentError",
                                 "error" => "synthetic failure", "handled" => true,
                                 "severity" => "warning", "source" => "spec.subscriber")
      expect(payload["context"]).to eq("user_id" => 42)
    end
  end

  it "still logs and does not raise when the counter fails" do
    allow(Yabeda.calendar.errors_reported_total).to receive(:increment).and_raise(RuntimeError, "no store")
    allow(Rails.logger).to receive(:warn)

    expect { described_class.new.report(ArgumentError.new("x"), handled: true, severity: :warning, context: {}) }
      .not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(/could not count ArgumentError/)
    expect(Rails.logger).to have_received(:warn).with(/"message":"error_reported"/)
  end

  it "uses unknown for a missing source" do
    allow(Rails.logger).to receive(:warn)

    expect { described_class.new.report(ArgumentError.new("x"), handled: true, severity: :warning, context: nil) }
      .to change { reported_count(**labels, source: "unknown") }.by(1)
  end
end
