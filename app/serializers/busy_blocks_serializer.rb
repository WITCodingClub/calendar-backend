# frozen_string_literal: true

# Renders the BusyBlocks of one user for the API. It sends only dates and
# times: no course, room, instructor, or calendar data.
class BusyBlocksSerializer
  def initialize(blocks, from:, to:)
    @blocks = blocks
    @from   = from
    @to     = to
  end

  def as_json(*)
    {
      time_zone:  Time.zone.tzinfo.name,
      start_date: @from.iso8601,
      end_date:   @to.iso8601,
      busy:       @blocks.map { |block| block_json(block) }
    }
  end

  private

  def block_json(block)
    {
      date:    block.date.iso8601,
      weekday: block.weekday,
      start:   block.start,
      end:     block.end
    }
  end
end
