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
end
