# frozen_string_literal: true

require "rails_helper"

RSpec.describe Brightspace::SyncPayload do
  let(:raw) { JSON.parse(file_fixture("brightspace/sync_snapshot.json").read) }

  def klass = raw["classes"][0]

  it "reads the fixture snapshot" do
    payload = described_class.new(raw)

    expect(payload.snapshot_id).to eq("8b451fe1-5c9c-44c6-86c6-846ac9a0a250")
    expect(payload.collected_at).to eq(Time.utc(2026, 10, 6, 17))
    expect(payload.classes.first[:assignments].map { |item| item[:kind] }).to eq(%w[assignment quiz])
    expect(payload.classes.first[:grades][:items].map { |item| item[:points_earned] }).to eq([ 9.5, nil, 0 ])
  end

  it "keeps a missing course_id apart from a null one" do
    expect(described_class.new(raw).classes.first[:course_id]).to eq(:absent)

    klass["course_id"] = nil
    expect(described_class.new(raw).classes.first[:course_id]).to be_nil
  end

  it "needs the top-level fields" do
    %w[snapshot_id host learner_id collected_at classes].each do |key|
      expect { described_class.new(raw.except(key)) }.to raise_error(ActionController::ParameterMissing, /#{key}/)
    end
  end

  it "rejects bad values with the path of the field" do
    klass["assignments"][1]["due_at"] = "next tuesday"

    expect { described_class.new(raw) }
      .to raise_error(described_class::Invalid, "classes[0].assignments[1].due_at must be an ISO 8601 time")
  end

  it "rejects an unknown assignment kind" do
    klass["assignments"][0]["kind"] = "survey"

    expect { described_class.new(raw) }.to raise_error(described_class::Invalid, /kind must be one of/)
  end

  it "rejects a complete section that the class does not send" do
    klass.delete("announcements")

    expect { described_class.new(raw) }
      .to raise_error(described_class::Invalid, /lists announcements, but the class has no announcements/)
  end

  it "rejects an unknown complete section" do
    klass["complete_sections"] << "quizzes"

    expect { described_class.new(raw) }.to raise_error(described_class::Invalid, /unknown section: quizzes/)
  end

  it "rejects the same class twice" do
    raw["classes"] << klass.deep_dup

    expect { described_class.new(raw) }.to raise_error(described_class::Invalid, /more than once/)
  end

  it "rejects the same item twice in a section" do
    klass["announcements"] << klass["announcements"][0].deep_dup

    expect { described_class.new(raw) }.to raise_error(described_class::Invalid, /more than once/)
  end

  it "accepts the same source id for two kinds" do
    klass["assignments"][1]["source_id"] = klass["assignments"][0]["source_id"]

    expect { described_class.new(raw) }.not_to raise_error
  end

  it "rejects a URL that is not http" do
    klass["assignments"][0]["source_url"] = "javascript:alert(1)"

    expect { described_class.new(raw) }.to raise_error(described_class::Invalid, /must be an http or https URL/)
  end

  it "rejects a snapshot from the future" do
    raw["collected_at"] = 1.day.from_now.iso8601

    expect { described_class.new(raw) }.to raise_error(described_class::Invalid, /future/)
  end

  it "rejects too many classes" do
    raw["classes"] = Array.new(described_class::MAX_CLASSES + 1) { |i| { "source_id" => i.to_s, "title" => "C#{i}" } }

    expect { described_class.new(raw) }.to raise_error(described_class::Invalid, /more than 100/)
  end

  it "rejects negative possible points" do
    klass["grades"]["items"][0]["points_possible"] = -1

    expect { described_class.new(raw) }.to raise_error(described_class::Invalid, /points_possible must be 0 or more/)
  end

  it "rejects a non-integer drop rule" do
    klass["grades"]["categories"][0]["drop_lowest"] = 1.5

    expect { described_class.new(raw) }.to raise_error(described_class::Invalid, /drop_lowest must be a whole number/)
  end

  it "accepts a null syllabus" do
    klass["syllabus"] = nil

    expect(described_class.new(raw).classes.first[:syllabus]).to be_nil
  end

  it "reads section errors" do
    klass["section_errors"] = { "grades" => "Gradebook timed out" }

    expect(described_class.new(raw).classes.first[:section_errors]).to eq("grades" => "Gradebook timed out")
  end
end
