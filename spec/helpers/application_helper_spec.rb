require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  describe '#titleize_with_roman_numerals' do
    it 'removes spaces between numbers and letters' do
      expect(helper.titleize_with_roman_numerals('Calculus 2 A')).to eq('Calculus 2A')
      expect(helper.titleize_with_roman_numerals('Physics 1 B')).to eq('Physics 1B')
      expect(helper.titleize_with_roman_numerals('chemistry 3 c')).to eq('Chemistry 3C')
    end

    it 'preserves Roman numerals' do
      expect(helper.titleize_with_roman_numerals('calculus ii')).to eq('Calculus II')
      expect(helper.titleize_with_roman_numerals('physics iv lab')).to eq('Physics IV Lab')
    end
  end

  describe '#normalize_section_number' do
    it 'removes spaces between digits and letters' do
      expect(helper.normalize_section_number('1 A')).to eq('1A')
      expect(helper.normalize_section_number('2 B')).to eq('2B')
      expect(helper.normalize_section_number('10 C')).to eq('10C')
    end

    it 'uppercases letters' do
      expect(helper.normalize_section_number('1a')).to eq('1A')
      expect(helper.normalize_section_number('2b')).to eq('2B')
    end

    it 'strips leading and trailing whitespace' do
      expect(helper.normalize_section_number('  1A  ')).to eq('1A')
      expect(helper.normalize_section_number(' 2 B ')).to eq('2B')
    end

    it 'handles already correct section numbers' do
      expect(helper.normalize_section_number('1A')).to eq('1A')
      expect(helper.normalize_section_number('2B')).to eq('2B')
    end

    it 'returns nil for blank input' do
      expect(helper.normalize_section_number(nil)).to be_nil
      expect(helper.normalize_section_number('')).to be_nil
      expect(helper.normalize_section_number('   ')).to be_nil
    end

    it 'handles numeric-only section numbers' do
      expect(helper.normalize_section_number('001')).to eq('001')
      expect(helper.normalize_section_number('123')).to eq('123')
    end
  end
end
