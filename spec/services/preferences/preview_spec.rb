# frozen_string_literal: true

require "rails_helper"

RSpec.describe Preferences::Preview do
  let(:context) { { title: "Data Structures", location: "Wentworth 210", course_code: "COMP2000" } }

  it "renders each template with the context" do
    preview = described_class.new.call({ title_template: "{{course_code}}", location_template: "Room: {{location}}" }, context)

    expect(preview).to eq(title: "COMP2000", description: "", location: "Room: Wentworth 210")
  end

  it "keeps the context values where no template is set" do
    expect(described_class.new.call({}, context)).to eq(title: "Data Structures", description: "", location: "Wentworth 210")
  end
end
