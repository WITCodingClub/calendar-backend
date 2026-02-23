# frozen_string_literal: true

require "rails_helper"

RSpec.describe PrerequisiteParserService, type: :service do
  subject(:call) { described_class.call(rule_text: rule_text) }

  describe "#call" do
    context "with a simple course code (spaced format)" do
      let(:rule_text) { "COMP 1000" }

      it "returns a course node" do
        expect(call).to eq({ type: "course", code: "COMP1000" })
      end
    end

    context "with a simple course code (no-space format)" do
      let(:rule_text) { "COMP1000" }

      it "returns a course node" do
        expect(call).to eq({ type: "course", code: "COMP1000" })
      end
    end

    context "with a 2-letter subject code" do
      let(:rule_text) { "CS 1000" }

      it "returns a course node" do
        expect(call).to eq({ type: "course", code: "CS1000" })
      end
    end

    context "with AND combination" do
      let(:rule_text) { "COMP 1000 and MATH 2300" }

      it "returns an and node with two operands" do
        expect(call).to eq({
                             type: "and",
                             operands: [
                               { type: "course", code: "COMP1000" },
                               { type: "course", code: "MATH2300" }
                             ]
                           })
      end
    end

    context "with OR combination" do
      let(:rule_text) { "COMP 1000 or COMP 1050" }

      it "returns an or node with two operands" do
        expect(call).to eq({
                             type: "or",
                             operands: [
                               { type: "course", code: "COMP1000" },
                               { type: "course", code: "COMP1050" }
                             ]
                           })
      end
    end

    context "with nested parenthesized expression" do
      let(:rule_text) { "COMP 1000 and (MATH 2300 or MATH 2100)" }

      it "returns an and node with a nested or" do
        expect(call).to eq({
                             type: "and",
                             operands: [
                               { type: "course", code: "COMP1000" },
                               {
                                 type: "or",
                                 operands: [
                                   { type: "course", code: "MATH2300" },
                                   { type: "course", code: "MATH2100" }
                                 ]
                               }
                             ]
                           })
      end
    end

    context "with 'Grade of X or better in COURSE' prefix format" do
      let(:rule_text) { "Grade of C or better in COMP 1000" }

      it "returns a course node with min_grade extracted" do
        expect(call).to eq({ type: "course", code: "COMP1000", min_grade: "C" })
      end
    end

    context "with 'COURSE with a grade of X or better' inline format" do
      let(:rule_text) { "COMP 1000 with a grade of C or better" }

      it "returns a course node with min_grade extracted" do
        expect(call).to eq({ type: "course", code: "COMP1000", min_grade: "C" })
      end
    end

    context "with 'Grade of B+ or better' with plus sign" do
      let(:rule_text) { "Grade of B+ or better in MATH 1777" }

      it "returns a course node with min_grade B+" do
        expect(call).to eq({ type: "course", code: "MATH1777", min_grade: "B+" })
      end
    end

    context "with 'Permission of instructor'" do
      let(:rule_text) { "Permission of instructor" }

      it "returns a special node" do
        expect(call[:type]).to eq("special")
        expect(call[:description]).to eq("Permission of instructor")
      end
    end

    context "with 'instructor consent'" do
      let(:rule_text) { "Consent of instructor required" }

      it "returns a special node" do
        expect(call[:type]).to eq("special")
      end
    end

    context "with three courses joined by AND" do
      let(:rule_text) { "COMP 1000 and MATH 2300 and COMP 2000" }

      it "returns an and node with three operands" do
        result = call
        expect(result[:type]).to eq("and")
        codes = result[:operands].pluck(:code)
        expect(codes).to contain_exactly("COMP1000", "MATH2300", "COMP2000")
      end
    end

    context "with complex nested parentheses" do
      let(:rule_text) { "(COMP 1000 and MATH 2300) or (COMP 1050 and MATH 1777)" }

      it "returns an or node with two and operands" do
        result = call
        expect(result[:type]).to eq("or")
        expect(result[:operands].length).to eq(2)
        expect(result[:operands][0][:type]).to eq("and")
        expect(result[:operands][1][:type]).to eq("and")
      end
    end
  end
end
