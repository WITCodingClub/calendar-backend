# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper do
  describe "#titleize_with_roman_numerals" do
    it "removes spaces between numbers and single standalone letters" do
      expect(helper.titleize_with_roman_numerals("Calculus 2 A")).to eq("Calculus 2A")
      expect(helper.titleize_with_roman_numerals("Physics 1 B")).to eq("Physics 1B")
      expect(helper.titleize_with_roman_numerals("chemistry 3 c")).to eq("Chemistry 3C")
    end

    it "preserves spaces before multi-letter words" do
      expect(helper.titleize_with_roman_numerals("Studio 02   Lab")).to eq("Studio 02   Lab")
      expect(helper.titleize_with_roman_numerals("Design 01 Lab")).to eq("Design 01 Lab")
      expect(helper.titleize_with_roman_numerals("Industrial Design Studio 4 Lab")).to eq("Industrial Design Studio 4 Lab")
    end

    it "preserves Roman numerals" do
      expect(helper.titleize_with_roman_numerals("calculus ii")).to eq("Calculus II")
      expect(helper.titleize_with_roman_numerals("physics iv lab")).to eq("Physics IV Lab")
      expect(helper.titleize_with_roman_numerals("English Ii")).to eq("English II")
      expect(helper.titleize_with_roman_numerals("Interior Studio Vii")).to eq("Interior Studio VII")
    end

    it "preserves acronyms in parentheses" do
      expect(helper.titleize_with_roman_numerals("Introduction To Building Information Modeling (BIM)")).to eq("Introduction To Building Information Modeling (BIM)")
      expect(helper.titleize_with_roman_numerals("Geographic Information Systems (GIS) For The Social Sciences")).to eq("Geographic Information Systems (GIS) For The Social Sciences")
    end

    it "preserves abbreviations like M.S. and Ph.D." do
      expect(helper.titleize_with_roman_numerals("M.S. Project Management Capstone")).to eq("M.S. Project Management Capstone")
    end

    it "preserves 3D and similar patterns" do
      expect(helper.titleize_with_roman_numerals("3D Realization 2")).to eq("3D Realization 2")
      expect(helper.titleize_with_roman_numerals("3 D Realization 2")).to eq("3D Realization 2")
    end

    it "handles complex cases with Roman numerals and labs" do
      expect(helper.titleize_with_roman_numerals("General Chemistry Ii   Lab")).to eq("General Chemistry II   Lab")
      expect(helper.titleize_with_roman_numerals("Engineering Physics Ii Lab")).to eq("Engineering Physics II Lab")
    end

    it "decodes HTML entities from LeopardWeb" do
      expect(helper.titleize_with_roman_numerals("Energy &amp; Resources In Architecture")).to eq("Energy & Resources In Architecture")
      expect(helper.titleize_with_roman_numerals("Cell &amp; Molecular Biology")).to eq("Cell & Molecular Biology")
      expect(helper.titleize_with_roman_numerals("Study Abroad &ndash; Cm Program")).to eq("Study Abroad – Cm Program")
    end
  end

  describe "#normalize_section_number" do
    it "removes spaces between digits and letters" do
      expect(helper.normalize_section_number("1 A")).to eq("1A")
      expect(helper.normalize_section_number("2 B")).to eq("2B")
      expect(helper.normalize_section_number("10 C")).to eq("10C")
    end

    it "uppercases letters" do
      expect(helper.normalize_section_number("1a")).to eq("1A")
      expect(helper.normalize_section_number("2b")).to eq("2B")
    end

    it "strips leading and trailing whitespace" do
      expect(helper.normalize_section_number("  1A  ")).to eq("1A")
      expect(helper.normalize_section_number(" 2 B ")).to eq("2B")
    end

    it "handles already correct section numbers" do
      expect(helper.normalize_section_number("1A")).to eq("1A")
      expect(helper.normalize_section_number("2B")).to eq("2B")
    end

    it "returns nil for blank input" do
      expect(helper.normalize_section_number(nil)).to be_nil
      expect(helper.normalize_section_number("")).to be_nil
      expect(helper.normalize_section_number("   ")).to be_nil
    end

    it "handles numeric-only section numbers" do
      expect(helper.normalize_section_number("001")).to eq("001")
      expect(helper.normalize_section_number("123")).to eq("123")
    end
  end
end
