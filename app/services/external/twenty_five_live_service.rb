# frozen_string_literal: true

module External
  class TwentyFiveLiveService < ApplicationService
    require "net/http"

    BASE_URL = "https://webservices.collegenet.com/r25ws/wrd/wit/run/"

    def call
      call!
    rescue => e
      Rails.logger.error("[TwentyFiveLiveService] #{e.class}: #{e.message}")
      false
    end

    def call!
      sync_organizations
      sync_event_categories
      sync_event_custom_attributes
      sync_resources
      check_constant_drift
      true
    end

    private

    def fetch(endpoint)
      uri = URI("#{BASE_URL}#{endpoint}.json")
      req = Net::HTTP::Get.new(uri)
      creds = Rails.application.credentials.dig(:TwentyFiveLive)
      req.basic_auth(creds[:username], creds[:password]) if creds
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
      raise "25Live API returned #{res.code} for #{endpoint}" unless res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body)
    end

    # ---------------------------------------------------------------------------
    # DB-backed syncs
    # ---------------------------------------------------------------------------

    def sync_organizations
      data = fetch("organizations")
      orgs = Array.wrap(data.dig("organizations", "organization") ||
                        data.dig("r25:organizations", "r25:organization"))

      orgs.each do |raw|
        id   = (raw["organization_id"] || raw["r25:organization_id"])&.to_i
        name = (raw["organization_name"] || raw["r25:organization_name"])&.strip
        next unless id && name.present?

        TwentyFiveLive::Organization
          .find_or_initialize_by(twenty_five_live_id: id)
          .tap do |org|
            org.assign_attributes(
              code: (raw["organization_code"] || raw["r25:organization_code"])&.strip,
              name: name,
              organization_type_name: (raw["organization_type_name"] || raw["r25:organization_type_name"])&.strip
            )
            org.save! if org.new_record? || org.changed?
          end
      end
    end

    def sync_event_categories
      data = fetch("evcat")
      cats = Array.wrap(data.dig("categories", "category") ||
                        data.dig("r25:categories", "r25:category"))

      cats.each do |raw|
        id   = (raw["category_id"] || raw["r25:category_id"])&.to_i
        name = (raw["category_name"] || raw["r25:category_name"])&.strip
        next unless id && name.present?

        TwentyFiveLive::EventCategory
          .find_or_initialize_by(twenty_five_live_id: id)
          .tap do |cat|
            cat.assign_attributes(
              name: name,
              sort_order: (raw["sort_order"] || raw["r25:sort_order"])&.to_i,
              defn_state: (raw["defn_state"] || raw["r25:defn_state"])&.to_i
            )
            cat.save! if cat.new_record? || cat.changed?
          end
      end
    end

    def sync_event_custom_attributes
      data = fetch("evatrb")
      attrs = Array.wrap(data.dig("custom_attributes", "custom_attribute") ||
                         data.dig("r25:custom_attributes", "r25:custom_attribute"))

      attrs.each do |raw|
        id   = (raw["custom_attribute_id"] || raw["r25:custom_attribute_id"])&.to_i
        name = (raw["custom_attribute_name"] || raw["r25:custom_attribute_name"])&.strip
        next unless id && name.present?

        TwentyFiveLive::EventCustomAttribute
          .find_or_initialize_by(twenty_five_live_id: id)
          .tap do |eca|
            eca.assign_attributes(
              name: name,
              attribute_type: raw["attribute_type"] || raw["r25:attribute_type"],
              attribute_type_name: (raw["attribute_type_name"] || raw["r25:attribute_type_name"])&.strip,
              multi_val: raw["multi_val"] || raw["r25:multi_val"],
              sort_order: (raw["sort_order"] || raw["r25:sort_order"])&.to_i,
              defn_state: (raw["defn_state"] || raw["r25:defn_state"])&.to_i
            )
            eca.save! if eca.new_record? || eca.changed?
          end
      end
    end

    def sync_resources
      data = fetch("resources")
      resources = Array.wrap(data.dig("resources", "resource") ||
                             data.dig("r25:resources", "r25:resource"))

      resources.each do |raw|
        id   = (raw["resource_id"] || raw["r25:resource_id"])&.to_i
        name = (raw["resource_name"] || raw["r25:resource_name"])&.strip
        next unless id && name.present?

        TwentyFiveLive::Resource
          .find_or_initialize_by(twenty_five_live_id: id)
          .tap do |res|
            res.assign_attributes(
              name: name,
              stock_level: (raw["stock_level"] || raw["r25:stock_level"])&.to_i,
              assign_perm: raw["assign_perm"] || raw["r25:assign_perm"],
              schedule_perm: raw["schedule_perm"] || raw["r25:schedule_perm"]
            )
            res.save! if res.new_record? || res.changed?
          end
      end
    end

    # ---------------------------------------------------------------------------
    # Constant drift detection
    # ---------------------------------------------------------------------------

    def check_constant_drift
      drifts = [
        diff_cabinets,
        diff_event_roles,
        diff_event_requirements,
        diff_event_types,
        diff_organization_categories,
        diff_organization_roles,
        diff_organization_custom_attributes,
        diff_organization_ratings,
        diff_organization_types,
        diff_resource_categories,
        diff_resource_custom_attributes,
        diff_space_categories,
        diff_space_custom_attributes,
        diff_space_features,
        diff_space_layouts,
      ].compact

      TwentyFiveLiveMailer.constant_drift_notification(drifts).deliver_later if drifts.any?
    end

    # --- event constant checks ---

    def diff_cabinets
      data     = fetch("cabinets")
      api_rows = Array.wrap(data.dig("cabinets", "cabinet") ||
                            data.dig("r25:cabinets", "r25:cabinet")).map do |raw|
        { id: raw["cabinet_id"]&.to_i, name: raw["cabinet_name"]&.strip,
          event_type_name: raw["event_type_name"]&.strip }
      end

      const_rows = TwentyFiveLive::Cabinet::CABINETS.map do |_k, v|
        { id: v[:id], name: v[:name], event_type_name: v[:event_type_name] }
      end

      build_drift("Cabinet", const_rows, api_rows, compare_keys: %i[name event_type_name])
    end

    def diff_event_roles
      data     = fetch("evcnrl")
      api_rows = Array.wrap(data.dig("roles", "role") ||
                            data.dig("r25:roles", "r25:role")).map do |raw|
        { id: raw["role_id"]&.to_i, name: raw["role_name"]&.strip,
          sort_order: raw["sort_order"]&.to_i, defn_state: raw["defn_state"]&.to_i }
      end

      const_rows = TwentyFiveLive::EventRole::EVENT_ROLES.map do |r|
        { id: r[:role_id], name: r[:role_name], sort_order: r[:sort_order], defn_state: r[:defn_state] }
      end

      build_drift("EventRole", const_rows, api_rows, compare_keys: %i[name sort_order defn_state])
    end

    def diff_event_requirements
      data     = fetch("evreq")
      api_rows = Array.wrap(data.dig("requirements", "requirement") ||
                            data.dig("r25:requirements", "r25:requirement")).map do |raw|
        { id: raw["requirement_id"]&.to_i, name: raw["requirement_name"]&.strip,
          sort_order: raw["sort_order"]&.to_i, defn_state: raw["defn_state"]&.to_i,
          stock_count: raw["stock_count"]&.to_i, allow_comment: raw["allow_comment"]&.to_i }
      end

      const_rows = TwentyFiveLive::EVENT_REQUIREMENTS.map do |r|
        { id: r[:requirement_id], name: r[:requirement_name], sort_order: r[:sort_order],
          defn_state: r[:defn_state], stock_count: r[:stock_count], allow_comment: r[:allow_comment] }
      end

      build_drift("EventRequirement", const_rows, api_rows,
                  compare_keys: %i[name sort_order defn_state stock_count allow_comment])
    end

    def diff_event_types
      data     = fetch("evtype")
      api_rows = Array.wrap(data.dig("event_types", "event_type") ||
                            data.dig("r25:event_types", "r25:event_type")).map do |raw|
        { id: raw["type_id"]&.to_i, name: raw["type_name"]&.strip }
      end

      const_rows = TwentyFiveLive::EventType::EVENT_TYPES.map do |t|
        { id: t[:type_id], name: t[:type_name] }
      end

      build_drift("EventType", const_rows, api_rows, compare_keys: %i[name])
    end

    # --- organization constant checks ---

    def diff_organization_categories
      data     = fetch("orgcat")
      api_rows = Array.wrap(data.dig("organization_categories", "category")).map do |raw|
        { id: raw["category_id"]&.to_i, name: raw["category_name"]&.strip,
          sort_order: raw["sort_order"]&.to_i, defn_state: raw["defn_state"]&.to_i }
      end

      const_rows = TwentyFiveLive::OrganizationCategory::ORGANIZATION_CATEGORIES.map do |c|
        { id: c[:category_id], name: c[:category_name], sort_order: c[:sort_order], defn_state: c[:defn_state] }
      end

      build_drift("OrganizationCategory", const_rows, api_rows,
                  compare_keys: %i[name sort_order defn_state])
    end

    def diff_organization_roles
      data     = fetch("orgcr")
      api_rows = Array.wrap(data.dig("organization_roles", "role")).map do |raw|
        { id: raw["role_id"]&.to_i, name: raw["role_name"]&.strip,
          sort_order: raw["sort_order"]&.to_i, defn_state: raw["defn_state"]&.to_i }
      end

      const_rows = TwentyFiveLive::OrganizationRole::ORGANIZATION_ROLES.map do |r|
        { id: r[:role_id], name: r[:role_name], sort_order: r[:sort_order], defn_state: r[:defn_state] }
      end

      build_drift("OrganizationRole", const_rows, api_rows,
                  compare_keys: %i[name sort_order defn_state])
    end

    def diff_organization_custom_attributes
      data     = fetch("orgat")
      api_rows = Array.wrap(data.dig("organization_custom_attributes", "attribute")).map do |raw|
        { id: raw["attribute_id"]&.to_i, name: raw["attribute_name"]&.strip,
          attribute_type: raw["attribute_type"].to_s, defn_state: raw["defn_state"]&.to_i }
      end

      const_rows = TwentyFiveLive::OrganizationCustomAttribute::ORGANIZATION_CUSTOM_ATTRIBUTES.map do |a|
        { id: a[:attribute_id], name: a[:attribute_name],
          attribute_type: a[:attribute_type].to_s, defn_state: a[:defn_state] }
      end

      build_drift("OrganizationCustomAttribute", const_rows, api_rows,
                  compare_keys: %i[name attribute_type defn_state])
    end

    def diff_organization_ratings
      data     = fetch("orgrtg")
      api_rows = Array.wrap(data.dig("organization_ratings", "rating")).map do |raw|
        { id: raw["rating_id"]&.to_i, name: raw["rating_name"]&.strip,
          sort_order: raw["sort_order"]&.to_i, defn_state: raw["defn_state"]&.to_i }
      end

      const_rows = TwentyFiveLive::OrganizationRating::ORGANIZATION_RATINGS.map do |r|
        { id: r[:rating_id], name: r[:rating_name], sort_order: r[:sort_order], defn_state: r[:defn_state] }
      end

      build_drift("OrganizationRating", const_rows, api_rows,
                  compare_keys: %i[name sort_order defn_state])
    end

    def diff_organization_types
      data     = fetch("orgtypes")
      api_rows = Array.wrap(data.dig("organization_types", "type")).map do |raw|
        rate = raw["rate_group"] || {}
        { id: raw["type_id"]&.to_i, name: raw["type_name"]&.strip,
          sort_order: raw["sort_order"]&.to_i, defn_state: raw["defn_state"]&.to_i,
          rate_group_id: rate["rate_group_id"].is_a?(Integer) ? rate["rate_group_id"] : nil,
          rate_group_name: rate["rate_group_name"].is_a?(String) ? rate["rate_group_name"]&.strip : nil }
      end

      const_rows = TwentyFiveLive::OrganizationType::ORGANIZATION_TYPES.map do |t|
        { id: t[:type_id], name: t[:type_name], sort_order: t[:sort_order],
          defn_state: t[:defn_state], rate_group_id: t[:rate_group_id],
          rate_group_name: t[:rate_group_name] }
      end

      build_drift("OrganizationType", const_rows, api_rows,
                  compare_keys: %i[name sort_order defn_state rate_group_id rate_group_name])
    end

    # --- resource constant checks ---

    def diff_resource_categories
      data     = fetch("rscat")
      api_rows = Array.wrap(data.dig("resource_categories", "category") ||
                            data.dig("r25:resource_categories", "r25:category")).map do |raw|
        { id: raw["category_id"]&.to_i, name: raw["category_name"]&.strip }
      end

      const_rows = TwentyFiveLive::ResourceCategory::RESOURCE_CATEGORIES.map do |c|
        { id: c[:category_id], name: c[:category_name] }
      end

      build_drift("ResourceCategory", const_rows, api_rows, compare_keys: %i[name])
    end

    def diff_resource_custom_attributes
      data     = fetch("resat")
      api_rows = Array.wrap(data.dig("resource_custom_attributes", "attribute") ||
                            data.dig("r25:resource_custom_attributes", "r25:attribute")).map do |raw|
        { id: raw["attribute_id"]&.to_i, name: raw["attribute_name"]&.strip,
          defn_state: raw["defn_state"]&.to_i }
      end

      const_rows = TwentyFiveLive::ResourceCustomAttribute::RESOURCE_CUSTOM_ATTRIBUTES.map do |a|
        { id: a[:attribute_id], name: a[:attribute_name], defn_state: a[:defn_state] }
      end

      build_drift("ResourceCustomAttribute", const_rows, api_rows, compare_keys: %i[name defn_state])
    end

    # --- space constant checks ---

    def diff_space_categories
      data     = fetch("rmcat")
      api_rows = Array.wrap(data.dig("space_categories", "category") ||
                            data.dig("r25:space_categories", "r25:category")).map do |raw|
        { id: raw["category_id"]&.to_i, name: raw["category_name"]&.strip }
      end

      const_rows = TwentyFiveLive::SpaceCategory::SPACE_CATEGORIES.map do |c|
        { id: c[:category_id], name: c[:category_name] }
      end

      build_drift("SpaceCategory", const_rows, api_rows, compare_keys: %i[name])
    end

    def diff_space_custom_attributes
      data     = fetch("rmat")
      api_rows = Array.wrap(data.dig("space_custom_attributes", "attribute") ||
                            data.dig("r25:space_custom_attributes", "r25:attribute")).map do |raw|
        { id: raw["attribute_id"]&.to_i, name: raw["attribute_name"]&.strip,
          defn_state: raw["defn_state"]&.to_i }
      end

      const_rows = TwentyFiveLive::SpaceCustomAttribute::SPACE_CUSTOM_ATTRIBUTES.map do |a|
        { id: a[:attribute_id], name: a[:attribute_name], defn_state: a[:defn_state] }
      end

      build_drift("SpaceCustomAttribute", const_rows, api_rows, compare_keys: %i[name defn_state])
    end

    def diff_space_features
      data     = fetch("rmfeat")
      api_rows = Array.wrap(data.dig("space_features", "feature") ||
                            data.dig("r25:space_features", "r25:feature")).map do |raw|
        { id: raw["feature_id"]&.to_i, name: raw["feature_name"]&.strip,
          defn_state: raw["defn_state"]&.to_i }
      end

      const_rows = TwentyFiveLive::SpaceFeature::SPACE_FEATURES.map do |f|
        { id: f[:feature_id], name: f[:feature_name], defn_state: f[:defn_state] }
      end

      build_drift("SpaceFeature", const_rows, api_rows, compare_keys: %i[name defn_state])
    end

    def diff_space_layouts
      data     = fetch("rmconf")
      api_rows = Array.wrap(data.dig("space_layouts", "layout") ||
                            data.dig("r25:space_layouts", "r25:layout")).map do |raw|
        { id: raw["layout_id"]&.to_i, name: raw["layout_name"]&.strip }
      end

      const_rows = TwentyFiveLive::SpaceLayout::SPACE_LAYOUTS.map do |l|
        { id: l[:layout_id], name: l[:layout_name] }
      end

      build_drift("SpaceLayout", const_rows, api_rows, compare_keys: %i[name])
    end

    # ---------------------------------------------------------------------------
    # Generic differ
    # ---------------------------------------------------------------------------

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
