# frozen_string_literal: true

module ApplicationHelper
  def titleize_with_roman_numerals(title)
    result = HTMLEntities.new.decode(title.to_s)

    preserved = {}
    counter = 0

    result = result.gsub(/\(([A-Z]{2,})\)/) do |match|
      key = "zzpreserved#{counter}zz"
      preserved[key] = match
      counter += 1
      key
    end

    result = result.gsub(/\b([A-Z]\.[A-Z]\.?)/) do |match|
      key = "zzpreserved#{counter}zz"
      preserved[key] = match
      counter += 1
      key
    end

    result = result.gsub(/\b(\d+[A-Z]+)\b/) do |match|
      key = "zzpreserved#{counter}zz"
      preserved[key] = match
      counter += 1
      key
    end

    result = result.gsub(/(\d)\s+([A-Za-z])(?=\s|$)/, '\1\2')

    result = result.downcase
                   .gsub(/(^|\s)(\w)/) { $1 + $2.upcase }
                   .gsub(/(\d)([a-z])/i) { $1 + $2.upcase }

    result = result.gsub(/\b(i{1,3}|iv|v|vi{1,3}|ix|x)\b/i) { |m| m.upcase }

    preserved.each { |key, val| result = result.gsub(key, val) }

    result
  end

  def normalize_section_number(section_number)
    return nil if section_number.blank?

    section_number.to_s.gsub(/^0+/, "").presence || "0"
  end
end
