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

  it "strips the space that a blank variable leaves in the location, as the sync does" do
    preview = described_class.new.call({ location_template: "{{building}} {{room}}" }, context.merge(building: "", room: "210"))

    expect(preview[:location]).to eq("210")
  end

  describe "#text" do
    it "leaves out each field with no template" do
      expect(described_class.new.text({ description_template: "{{title}}" }, context)).to eq(description: "Data Structures")
    end
  end
end
