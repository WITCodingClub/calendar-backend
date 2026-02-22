# frozen_string_literal: true

class TermSerializer
  def initialize(term)
    @term = term
  end

  def as_json(*)
    return nil if @term.nil?

    {
      name: @term.name,
      id: @term.uid,
      pub_id: @term.public_id,
      start_date: @term.start_date,
      end_date: @term.end_date
    }
  end

end
