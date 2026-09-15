# frozen_string_literal: true

module MicrosoftGraph
  # Turns the app's event color into an Outlook category.
  #
  # Google takes a color id on each event. Outlook colors an event through its
  # categories, and each category in the person's master list has one preset
  # color. The app uses one "WIT <color>" category for each Google color. It
  # reuses a category with that name when the person already has one, and does
  # not change the color the person gave it.
  #
  # One instance lives for one sync, so the master list is read at most once
  # and each category is created at most once per sync.
  #
  # The master list needs the MailboxSettings.ReadWrite scope. Without it Graph
  # answers 403. The event still gets the category name, and Outlook shows it
  # without a color.
  class CategoryCache
    PREFIX = "WIT "

    # Google event color id => [name, closest Outlook preset].
    COLORS = {
      1  => [ "Lavender",  "preset7" ],
      2  => [ "Sage",      "preset4" ],
      3  => [ "Grape",     "preset8" ],
      4  => [ "Flamingo",  "preset9" ],
      5  => [ "Banana",    "preset3" ],
      6  => [ "Tangerine", "preset1" ],
      7  => [ "Peacock",   "preset5" ],
      8  => [ "Graphite",  "preset12" ],
      9  => [ "Blueberry", "preset22" ],
      10 => [ "Basil",     "preset19" ],
      11 => [ "Tomato",    "preset0" ]
    }.freeze

    NAMES = COLORS.values.map { |name, _preset| "#{PREFIX}#{name}" }.freeze

    def self.app_category?(name)
      NAMES.include?(name)
    end

    def initialize(client)
      @client = client
      @names  = {}
    end

    # The category name for a color id, or nil when the event has no color.
    def name_for(color_id)
      name, preset = COLORS[color_id.to_i]
      return nil unless name

      category = "#{PREFIX}#{name}"
      @names.fetch(category) { @names[category] = ensure_category(category, preset) }
    end

    private

    attr_reader :client

    def ensure_category(name, preset)
      return name if master_names.nil? || master_names.include?(name.downcase)

      client.post("me/outlook/masterCategories", { displayName: name, color: preset })
      master_names << name.downcase
      name
    rescue MicrosoftGraph::Error => e
      # 409 means another sync created it first.
      log_failure("create", e) unless e.status == 409
      name
    end

    # nil when the list cannot be read, so no create is tried either.
    def master_names
      return @master_names if defined?(@master_names)

      response = client.get("me/outlook/masterCategories", params: { "$select" => "displayName" })
      @master_names = response.fetch("value", []).map { |category| category["displayName"].to_s.downcase }
    rescue MicrosoftGraph::AuthError
      raise
    rescue MicrosoftGraph::Error => e
      log_failure("list", e)
      @master_names = nil
    end

    def log_failure(action, error)
      Rails.logger.warn({ message: "Could not #{action} Outlook master categories", status: error.status }.to_json)
    end
  end
end
