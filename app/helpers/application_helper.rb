module ApplicationHelper
  def titleize_with_roman_numerals(title)
    # Capitalize first letter of each word while preserving punctuation
    # Also capitalize letters that follow digits (e.g., "1B" in "Calculus 1B")
    titleized = title.downcase
      .gsub(/(^|\s)(\w)/) { $1 + $2.upcase }  # Capitalize after space or start
      .gsub(/(\d)([a-z])/) { $1 + $2.upcase }  # Capitalize letters after digits

    # Then fix Roman numerals (I, II, III, IV, V, etc.)
    # Match Roman numerals as separate words
    titleized.gsub(/\b(i{1,3}|iv|v|vi{1,3}|ix|x)\b/i) do |match|
      match.upcase
    end
  end
end
