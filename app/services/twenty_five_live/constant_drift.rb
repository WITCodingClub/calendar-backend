# frozen_string_literal: true

module TwentyFiveLive
  # Compares the constants in app/lib/twenty_five_live/ with the rows that
  # 25Live sends now, and returns the differences: rows added, removed, or
  # changed. One table describes each endpoint, so a new constant set needs
  # one more row in CHECKS.
  class ConstantDrift
    # entity: the name in the drift mail. endpoint and list: where the rows are
    # in the 25Live response. key: the prefix of the id and name keys, such as
    # "role" for role_id and role_name. fields: the other values to compare,
    # each with the method that casts it, or a lambda that reads it from the
    # row. constants: the rows of the constant, with the same keys as the
    # 25Live rows.
    Check = Data.define(:entity, :endpoint, :list, :key, :fields, :constants)

    # 25Live nests the rate group, and sends a missing one as a value that is
    # not an Integer or a String.
    RATE_GROUP_ID   = ->(read) { read.call("rate_group").then { |g| g["rate_group_id"] if g.is_a?(Hash) }.then { |v| v if v.is_a?(Integer) } }
    RATE_GROUP_NAME = ->(read) { read.call("rate_group").then { |g| g["rate_group_name"] if g.is_a?(Hash) }.then { |v| v.strip if v.is_a?(String) } }
    STATE           = { sort_order: :to_i, defn_state: :to_i }.freeze

    CHECKS = [
      Check.new("Cabinet", "cabinets", %w[cabinets cabinet], "cabinet", { event_type_name: :strip },
                -> { Cabinet::CABINETS.values.map { |c| { cabinet_id: c[:id], cabinet_name: c[:name], event_type_name: c[:event_type_name] } } }),
      Check.new("EventRole", "evcnrl", %w[roles role], "role", STATE, -> { EventRole::EVENT_ROLES }),
      Check.new("EventRequirement", "evreq", %w[requirements requirement], "requirement",
                STATE.merge(stock_count: :to_i, allow_comment: :to_i), -> { EventRequirement::EVENT_REQUIREMENTS }),
      Check.new("EventType", "evtype", %w[event_types event_type], "type", {}, -> { EventType::EVENT_TYPES }),
      Check.new("OrganizationCategory", "orgcat", %w[organization_categories category], "category", STATE,
                -> { OrganizationCategory::ORGANIZATION_CATEGORIES }),
      Check.new("OrganizationRole", "orgcr", %w[organization_roles role], "role", STATE,
                -> { OrganizationRole::ORGANIZATION_ROLES }),
      Check.new("OrganizationCustomAttribute", "orgat", %w[organization_custom_attributes attribute], "attribute",
                { attribute_type: :to_s, defn_state: :to_i },
                -> { OrganizationCustomAttribute::ORGANIZATION_CUSTOM_ATTRIBUTES }),
      Check.new("OrganizationRating", "orgrtg", %w[organization_ratings rating], "rating", STATE,
                -> { OrganizationRating::ORGANIZATION_RATINGS }),
      Check.new("OrganizationType", "orgtypes", %w[organization_types type], "type",
                STATE.merge(rate_group_id: RATE_GROUP_ID, rate_group_name: RATE_GROUP_NAME),
                lambda {
                  OrganizationType::ORGANIZATION_TYPES.map do |t|
                    t.merge(rate_group: { "rate_group_id" => t[:rate_group_id], "rate_group_name" => t[:rate_group_name] })
                  end
                }),
      Check.new("ResourceCategory", "rscat", %w[resource_categories category], "category", {},
                -> { ResourceCategory::RESOURCE_CATEGORIES }),
      Check.new("ResourceCustomAttribute", "resat", %w[resource_custom_attributes attribute], "attribute",
                { defn_state: :to_i }, -> { ResourceCustomAttribute::RESOURCE_CUSTOM_ATTRIBUTES }),
      Check.new("SpaceCategory", "rmcat", %w[space_categories category], "category", {},
                -> { SpaceCategory::SPACE_CATEGORIES }),
      Check.new("SpaceCustomAttribute", "rmat", %w[space_custom_attributes attribute], "attribute",
                { defn_state: :to_i }, -> { SpaceCustomAttribute::SPACE_CUSTOM_ATTRIBUTES }),
      Check.new("SpaceFeature", "rmfeat", %w[space_features feature], "feature", { defn_state: :to_i },
                -> { SpaceFeature::SPACE_FEATURES }),
      Check.new("SpaceLayout", "rmconf", %w[space_layouts layout], "layout", {}, -> { SpaceLayout::SPACE_LAYOUTS })
    ].freeze

    # fetch: reads one endpoint and returns the parsed JSON.
    def initialize(fetch)
      @fetch = fetch
    end

    # One drift hash for each entity that changed. A check whose request fails
    # is skipped, so one broken endpoint does not hide the others.
    def call
      CHECKS.filter_map do |check|
        diff(check)
      rescue Client::RequestError => e
        Rails.logger.warn("[TwentyFiveLive::ConstantDrift] Skipping #{check.entity} (#{e.message})")
        nil
      end
    end

    private

    def diff(check)
      data = @fetch.call(check.endpoint)
      raw_rows = Array.wrap(data.dig(*check.list) || data.dig(*check.list.map { |k| "r25:#{k}" }))
      api_rows = raw_rows.map { |raw| row(check, ->(k) { raw[k] || raw["r25:#{k}"] }) }
      const_rows = check.constants.call.map { |c| row(check, ->(k) { c[k.to_sym] }) }

      build_drift(check.entity, const_rows, api_rows, compare_keys: [ :name, *check.fields.keys ])
    end

    def row(check, read)
      fields = check.fields.to_h do |field, reader|
        [ field, reader.is_a?(Proc) ? reader.call(read) : read.call(field.to_s)&.public_send(reader) ]
      end
      { id: read.call("#{check.key}_id")&.to_i, name: read.call("#{check.key}_name")&.strip, **fields }
    end

    def build_drift(entity, const_rows, api_rows, compare_keys:)
      const_by_id = const_rows.index_by { |r| r[:id] }
      api_by_id   = api_rows.index_by   { |r| r[:id] }

      added   = (api_by_id.keys - const_by_id.keys).map { |id| { id: id, name: api_by_id[id][:name] } }
      removed = (const_by_id.keys - api_by_id.keys).map { |id| { id: id, name: const_by_id[id][:name] } }
      changed = const_by_id.keys.intersection(api_by_id.keys).filter_map do |id|
        was = const_by_id[id].slice(*compare_keys)
        now = api_by_id[id].slice(*compare_keys)
        { id: id, name: api_by_id[id][:name], was: was, now: now } if was != now
      end

      return nil if added.empty? && removed.empty? && changed.empty?

      { entity: entity, added: added, removed: removed, changed: changed }
    end
  end
end
