# frozen_string_literal: true

require "rails_helper"

RSpec.describe Faculties::DirectoryMerge do
  describe ".name_parts" do
    it "splits first, middle, and last names" do
      expect(described_class.name_parts("Ada  King Lovelace")).to eq(first_name: "Ada", middle_name: "King", last_name: "Lovelace")
      expect(described_class.name_parts("Plato")).to eq(first_name: "Plato", last_name: "Plato")
      expect(described_class.name_parts(nil)).to eq({})
    end
  end

  describe ".apply" do
    let(:faculty) { create(:faculty, first_name: "Al", last_name: "Lo", title: "Lecturer", department: "Math", employee_type: nil) }

    it "keeps the longer name, updates a changed title, and fills a blank field once" do
      changed = described_class.apply(faculty, { display_name: "Alan Lovelace", title: "Professor", department: "Physics" })

      expect(changed).to be(true)
      expect(faculty.reload).to have_attributes(first_name: "Alan", last_name: "Lovelace", title: "Professor",
                                                department: "Math", employee_type: "faculty")
      expect(faculty.directory_last_synced_at).to be_present
    end

    it "calls a title with no teaching word staff" do
      described_class.apply(faculty, { display_name: "Al Lo", title: "Registrar" })

      expect(faculty.reload.employee_type).to eq("staff")
    end
  end
end
