# frozen_string_literal: true

module Catalog
  # One request for a page of a catalog list: the filters, the page, the
  # total, and the rows as the Catalog:: serializers give them. The REST
  # controllers and the MCP search tools render it, and the GraphQL schema
  # pages the same scope with its connections. Each list names its query
  # object, which declares the filters (Catalog::Filters).
  class ListRequest
    List = Data.define(:query, :includes, :count, :rows, :meta)

    LISTS = {
      sections:    List.new(
        query:    SectionQuery,
        includes: ->(relation) { SectionQuery.with_associations(relation) },
        # A section joins its instructors, so it can repeat in the relation.
        count:    ->(relation) { relation.count("DISTINCT courses.id") },
        rows:     ->(records) { SectionSerializer.collection(records) },
        meta:     {}
      ),
      courses:     List.new(
        query:    CourseQuery,
        includes: :itself.to_proc,
        count:    :count.to_proc,
        rows:     ->(records) { records.map { |course| CourseSerializer.summary(course) } },
        meta:     {}
      ),
      instructors: List.new(
        query:    InstructorQuery,
        includes: :itself.to_proc,
        count:    :count.to_proc,
        rows:     ->(records) { records.map { |faculty| InstructorSerializer.new(faculty).as_json } },
        meta:     {}
      ),
      reviews:     List.new(
        query:    ReviewQuery,
        includes: ->(relation) { ReviewQuery.with_associations(relation) },
        count:    :count.to_proc,
        rows:     ->(records) { records.map { |review| ReviewSerializer.new(review).as_json } },
        meta:     { source: ReviewSerializer::SOURCE }
      )
    }.freeze

    def self.query(list) = LISTS.fetch(list).query

    # The whole filtered list with what its rows read, for a GraphQL
    # connection, which pages it itself.
    def self.scope(list, filters)
      config = LISTS.fetch(list)
      config.includes.call(config.query.new.call(**filters))
    end

    attr_reader :filters, :page

    # filters: the filters of the list's query object. page and per_page as
    # the caller sent them (Catalog::Page). surface: :api or :mcp, for the
    # page sizes.
    def initialize(list, filters, page: nil, per_page: nil, surface: :api)
      @list    = LISTS.fetch(list)
      @filters = filters
      @page    = Page.new(list, page: page, per_page: per_page, surface: surface)
    end

    def rows
      @list.rows.call(page.of(@list.includes.call(relation)))
    end

    def meta
      page.meta(@list.count.call(relation)).merge(@list.meta)
    end

    private

    def relation
      @relation ||= @list.query.new.call(**filters)
    end
  end
end
