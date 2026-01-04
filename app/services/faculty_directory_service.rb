# frozen_string_literal: true

# Service to scrape and parse the WIT Faculty/Staff Directory.
#
# @example Fetch all faculty
#   result = FacultyDirectoryService.call
#   # => { success: true, faculty: [...], total_count: 809 }
#
# @example Fetch single page
#   result = FacultyDirectoryService.new(page: 0, fetch_all: false).call
#
# @example Search by name
#   result = FacultyDirectoryService.new(search: "Smith", fetch_all: false).call
#
class FacultyDirectoryService < ApplicationService
  require "faraday"
  require "nokogiri"

  BASE_URL = "https://wit.edu/faculty-staff-directory"
  RESULTS_PER_PAGE = 12

  attr_reader :page, :fetch_all, :employee_type, :search

  def initialize(page: nil, fetch_all: true, employee_type: "All", search: nil)
    @page = page
    @fetch_all = fetch_all
    @employee_type = employee_type
    @search = search
    super()
  end

  def call
    if fetch_all && page.nil? && search.nil?
      fetch_all_pages
    else
      fetch_single_page(page || 0)
    end
  rescue => e
    Rails.logger.error("[FacultyDirectoryService] Error: #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n"))
    { success: false, error: e.message, faculty: [], total_count: 0 }
  end

  def call!
    result = call
    raise result[:error] unless result[:success]

    result
  end

  private

  def fetch_all_pages
    all_faculty = []
    current_page = 0
    total_count = nil

    loop do
      result = fetch_single_page(current_page)
      break unless result[:success]

      total_count ||= result[:total_count]
      all_faculty.concat(result[:faculty])

      Rails.logger.info("[FacultyDirectoryService] Fetched page #{current_page}, total: #{all_faculty.length}/#{total_count}")

      # Break if we've fetched all pages
      break if all_faculty.length >= total_count || result[:faculty].empty?

      current_page += 1

      # Small delay to be respectful to the server
      sleep(0.3)
    end

    {
      success: true,
      faculty: all_faculty,
      total_count: total_count || all_faculty.length
    }
  end

  def fetch_single_page(page_num)
    cache_key = "faculty_directory:page:#{page_num}:#{employee_type}:#{search}"

    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      params = {
        page: page_num,
        employee_type: employee_type
      }
      params[:search] = search if search.present?

      response = connection.get("", params)

      if response.success?
        parse_directory_page(response.body)
      else
        { success: false, error: "HTTP #{response.status}", faculty: [], total_count: 0 }
      end
    end
  end

  def connection
    @connection ||= Faraday.new(url: BASE_URL) do |faraday|
      faraday.request :url_encoded
      faraday.headers["User-Agent"] = "WITCalendarBot/1.0"
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
      faraday.options.open_timeout = 10
    end
  end

  def parse_directory_page(html)
    doc = Nokogiri::HTML(html)

    # Extract total count from "Showing X - Y of Z results"
    total_count = extract_total_count(doc)

    # Find all faculty cards - try multiple selectors
    faculty_list = []
    cards = find_faculty_cards(doc)

    cards.each do |card|
      faculty_data = parse_faculty_card(card)
      faculty_list << faculty_data if faculty_data[:email].present?
    end

    { success: true, faculty: faculty_list, total_count: total_count }
  end

  def find_faculty_cards(doc)
    # Try various selectors for the faculty cards
    selectors = [
      ".views-row",
      ".directory-card",
      ".faculty-card",
      ".profile-card",
      "[class*='directory-item']",
      ".view-content > div"
    ]

    selectors.each do |selector|
      cards = doc.css(selector)
      return cards if cards.any?
    end

    # Fallback: try to find cards by structure (divs containing email links)
    doc.css("div").select { |div| div.at_css('a[href^="mailto:"]') }
  end

  def extract_total_count(doc)
    # Look for "Showing 1 - 12 of 809 results" text
    selectors = [".result-count", ".pager-summary", ".view-header", "h2", "h3"]

    selectors.each do |selector|
      doc.css(selector).each do |element|
        text = element.text
        match = text.match(/of\s+(\d+)\s+results?/i)
        return match[1].to_i if match
      end
    end

    # If not found, try the entire page text
    match = doc.text.match(/of\s+(\d+)\s+results?/i)
    match ? match[1].to_i : 0
  end

  def parse_faculty_card(card)
    {
      display_name: extract_name(card),
      title: extract_title(card),
      email: extract_email(card),
      phone: extract_phone(card),
      office_location: extract_office(card),
      department: extract_department(card),
      school: extract_school(card),
      photo_url: extract_photo_url(card),
      profile_url: extract_profile_url(card),
      raw_html: card.to_html
    }
  end

  def extract_name(card)
    # For WIT directory, name is in h2, optionally with a span inside
    h2 = card.at_css("h2")
    if h2
      # Check for span inside h2 first
      span = h2.at_css("span")
      name_text = span&.text&.strip || h2.text.strip

      # Clean up the name - remove any nested h3 content that might get included
      h3_in_h2 = h2.at_css("h3")
      if h3_in_h2
        name_text = name_text.sub(h3_in_h2.text.strip, "").strip
      end

      return name_text if name_text.present? && name_text.exclude?("@")
    end

    # Fallback: try link text for profile links
    link = card.at_css('a[href*="/directory/"]')
    link&.text&.strip
  end

  def extract_title(card)
    # For WIT directory, title/position is in h3 (separate from h2 which has the name)
    # Try h3 first but only if it's not inside h2
    h3 = card.at_css("h3")
    if h3
      # Make sure this h3 is not nested inside h2
      parent_h2 = h3.ancestors("h2").first
      if parent_h2.nil?
        text = h3.text.strip
        return text if text.present? && text.exclude?("@")
      end
    end

    # Try other selectors for job title
    selectors = [".field--name-field-job-titles", ".field--name-field-job-title", ".title", ".position", ".job-title"]
    selectors.each do |selector|
      node = card.at_css(selector)
      next unless node

      text = node.text.strip
      return text if text.present? && text.exclude?("@")
    end

    nil
  end

  def extract_email(card)
    # Try href="mailto:" first
    mailto = card.at_css('a[href^="mailto:"]')
    if mailto
      email = mailto["href"].sub("mailto:", "").strip
      return email.downcase if email.include?("@")
    end

    # Try text content containing @wit.edu
    card.text.scan(/[\w.+-]+@wit\.edu/i).first&.downcase
  end

  def extract_phone(card)
    # Look for phone patterns in the text
    selectors = [".phone", ".telephone", ".field--name-field-phone", "[class*='phone']"]

    selectors.each do |selector|
      node = card.at_css(selector)
      return node.text.strip if node && node.text.strip =~ /\d{3}[-.\s]?\d{3}[-.\s]?\d{4}/
    end

    # Try to find phone number pattern in text (617-xxx-xxxx)
    phone_match = card.text.match(/(617[-.\s]?\d{3}[-.\s]?\d{4})/)
    phone_match ? phone_match[1].gsub(/[^\d-]/, "") : nil
  end

  def extract_office(card)
    # Try specific selectors first
    selectors = [
      ".field--name-field-physical-location",
      ".field--name-field-office-location",
      ".office",
      ".location",
      "[class*='office']",
      "[class*='location']"
    ]

    selectors.each do |selector|
      node = card.at_css(selector)
      if node
        text = node.text.strip
        return text if text.present? && text.exclude?("@") && !looks_like_phone?(text)
      end
    end

    # Look for building names in p tags
    buildings = ["Beatty", "Dobbs", "Williston", "Annex", "Nelson", "Ira Allen", "Wentworth", "Tansey", "Hall", "Gym", "Center"]
    card.css("p").each do |p|
      text = p.text.strip
      next if text.include?("@") || looks_like_phone?(text)

      if buildings.any? { |b| text.include?(b) }
        return text
      end
    end

    # General building pattern match from card text
    buildings.each do |building|
      match = card.text.match(/(#{building}[^,\n@]*(?:Hall|Center|Gym)?(?:\s*[-–]\s*\d+[A-Z]?)?)/i)
      if match
        result = match[1].strip
        return result unless looks_like_phone?(result)
      end
    end

    nil
  end

  def looks_like_phone?(text)
    text.match?(/\d{3}[-.\s]?\d{3}[-.\s]?\d{4}/)
  end

  def extract_department(card)
    selectors = [".field--name-field-department", ".department", "[class*='department']"]

    selectors.each do |selector|
      node = card.at_css(selector)
      return node.text.strip if node && node.text.strip.present?
    end

    # Try to find department-like text in p tags
    # Departments often have keywords like these
    dept_keywords = ["Department", "Sciences", "Engineering", "Computing", "Management", "Architecture", "CEIS"]
    card.css("p").each do |p|
      text = p.text.strip
      next if text.include?("@") || looks_like_phone?(text)
      next if text.length > 100 # Probably not a department name

      next unless dept_keywords.any? { |k| text.include?(k) }
      # Make sure it's not a building or office
      next if text.include?("Hall") || text.include?("Gym") || text.include?("Center")

      return text
    end

    nil
  end

  def extract_school(card)
    selectors = [".field--name-field-school", ".school", ".college", "[class*='school']"]

    selectors.each do |selector|
      node = card.at_css(selector)
      return node.text.strip if node && node.text.strip.present?
    end

    # Try to extract from title if it contains school info
    title = extract_title(card)
    if title
      schools = [
        "School of Engineering",
        "School of Computing & Data Science",
        "School of Management",
        "School of Architecture",
        "School of Sciences and Humanities"
      ]
      schools.each do |school|
        return school if title.include?(school)
      end
    end

    nil
  end

  def extract_photo_url(card)
    img = card.at_css("img")
    return nil unless img

    src = img["src"] || img["data-src"]
    return nil if src.blank?
    return nil if src.include?("placeholder") || src.include?("Icon_User")

    # Make absolute URL if relative
    if src.start_with?("/")
      "https://wit.edu#{src}"
    else
      src
    end
  end

  def extract_profile_url(card)
    link = card.at_css('a[href*="/directory/"]')
    return nil unless link

    href = link["href"]
    if href.start_with?("/")
      "https://wit.edu#{href}"
    else
      href
    end
  end

end
