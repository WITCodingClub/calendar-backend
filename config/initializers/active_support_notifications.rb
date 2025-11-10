# frozen_string_literal: true

# Subscribe to ActiveSupport::Notifications to send metrics to StatsD
# This tracks database queries, cache operations, view rendering, and more

# Helper method to extract SQL operation type
def extract_sql_operation(sql)
  return "unknown" if sql.blank?

  case sql
  when /^SELECT/i
    "select"
  when /^INSERT/i
    "insert"
  when /^UPDATE/i
    "update"
  when /^DELETE/i
    "delete"
  when /^BEGIN/i
    "begin"
  when /^COMMIT/i
    "commit"
  when /^ROLLBACK/i
    "rollback"
  when /^CREATE/i
    "create"
  when /^ALTER/i
    "alter"
  when /^DROP/i
    "drop"
  else
    "other"
  end
end

# Track SQL queries
ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, start, finish, _id, payload|
  duration = (finish - start) * 1000.0 # Convert to milliseconds

  # Don't track schema queries or SHOW queries
  unless payload[:name]&.include?("SCHEMA") || payload[:sql]&.match?(/^(SHOW|DESCRIBE|EXPLAIN)/)
    operation = extract_sql_operation(payload[:sql])

    tags = [
      "operation:#{operation}",
      "cached:#{payload[:cached] || false}"
    ]

    # Add table name if we can extract it
    if payload[:name].present? && !payload[:name].include?("ActiveRecord::")
      tags << "model:#{payload[:name]}"
    end

    StatsD.measure("database.query.duration", duration, tags: tags)
    StatsD.increment("database.query.count", tags: tags)
  end
end

# Track cache operations
%w[read write delete exist? fetch].each do |operation|
  ActiveSupport::Notifications.subscribe("cache_#{operation}.active_support") do |_name, start, finish, _id, payload|
    duration = (finish - start) * 1000.0

    tags = [
      "operation:#{operation}",
      "hit:#{payload[:hit] || false}"
    ]

    # Add super_operation for fetch (read/write)
    if payload[:super_operation]
      tags << "super_operation:#{payload[:super_operation]}"
    end

    StatsD.measure("cache.operation.duration", duration, tags: tags)
    StatsD.increment("cache.operation.count", tags: tags)

    # Track cache hits/misses for read and fetch operations
    if %w[read fetch].include?(operation)
      if payload[:hit]
        StatsD.increment("cache.hit", tags: ["operation:#{operation}"])
      else
        StatsD.increment("cache.miss", tags: ["operation:#{operation}"])
      end
    end
  end
end

# Track view rendering
ActiveSupport::Notifications.subscribe("render_template.action_view") do |_name, start, finish, _id, payload|
  duration = (finish - start) * 1000.0

  tags = [
    "format:#{payload[:identifier]&.split('.')&.last || 'unknown'}"
  ]

  StatsD.measure("view.render.duration", duration, tags: tags)
  StatsD.increment("view.render.count", tags: tags)
end

# Track partial rendering
ActiveSupport::Notifications.subscribe("render_partial.action_view") do |_name, start, finish, _id, payload|
  duration = (finish - start) * 1000.0

  StatsD.measure("view.partial.duration", duration)
  StatsD.increment("view.partial.count")
end

# Track Action Mailer deliveries
ActiveSupport::Notifications.subscribe("deliver.action_mailer") do |_name, start, finish, _id, payload|
  duration = (finish - start) * 1000.0

  tags = [
    "mailer:#{payload[:mailer]}"
  ]

  StatsD.measure("mailer.deliver.duration", duration, tags: tags)
  StatsD.increment("mailer.deliver.count", tags: tags)
end

# Track Active Storage uploads
ActiveSupport::Notifications.subscribe("service_upload.active_storage") do |_name, start, finish, _id, payload|
  duration = (finish - start) * 1000.0

  tags = [
    "service:#{payload[:service]}"
  ]

  StatsD.measure("storage.upload.duration", duration, tags: tags)
  StatsD.increment("storage.upload.count", tags: tags)
end

# Track Active Storage downloads
ActiveSupport::Notifications.subscribe("service_download.active_storage") do |_name, start, finish, _id, payload|
  duration = (finish - start) * 1000.0

  tags = [
    "service:#{payload[:service]}"
  ]

  StatsD.measure("storage.download.duration", duration, tags: tags)
  StatsD.increment("storage.download.count", tags: tags)
end
