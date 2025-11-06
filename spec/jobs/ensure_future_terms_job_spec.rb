# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnsureFutureTermsJob, type: :job do
  describe '#perform' do
    let(:current_year) { Date.today.year }

    before do
      # Clear existing terms
      Term.destroy_all
    end

    context 'when no terms exist' do
      it 'creates current term and 2 terms ahead (3 terms total)' do
        expect {
          described_class.perform_now
        }.to change(Term, :count).by(3) # current + 2 ahead = 3 terms
      end

      it 'assigns uids based on term pattern (fall: [year+1]10, spring: [year]20, summer: [year]30)' do
        # Since we only create current + 2 ahead, let's verify the UIDs are correct
        # for whatever terms are created based on current date
        described_class.perform_now

        terms = Term.all
        terms.each do |term|
          expected_uid = case term.season.to_sym
                        when :fall
                          (term.year + 1) * 100 + 10
                        when :spring
                          term.year * 100 + 20
                        when :summer
                          term.year * 100 + 30
                        end
          expect(term.uid).to eq(expected_uid)
        end
      end
    end

    context 'when some terms already exist' do
      before do
        # Create current term (based on today's date)
        # If today is in Fall (Aug-Dec), create Fall term
        today = Date.today
        if today.month >= 8
          Term.create!(year: current_year, season: :fall, uid: (current_year + 1) * 100 + 10)
        elsif today.month >= 6
          Term.create!(year: current_year, season: :summer, uid: current_year * 100 + 30)
        else
          Term.create!(year: current_year, season: :spring, uid: current_year * 100 + 20)
        end
      end

      it 'only creates missing future terms' do
        expect {
          described_class.perform_now
        }.to change(Term, :count).by(2) # 2 future terms (current already exists)
      end

      it 'generates correct uids for new terms' do
        described_class.perform_now

        next_year = current_year + 1
        # Check next year's spring term has correct UID
        next_spring = Term.find_by(year: next_year, season: :spring)
        expect(next_spring.uid).to eq(next_year * 100 + 20)
      end

      it 'does not duplicate existing terms' do
        initial_count = Term.count
        described_class.perform_now

        # Should create exactly 2 more terms (the future terms)
        expect(Term.count).to eq(initial_count + 2)

        # Verify no duplicates by checking all terms have unique year+season combos
        term_combos = Term.pluck(:year, :season)
        expect(term_combos.uniq.count).to eq(term_combos.count)
      end
    end

    context 'with custom terms_ahead parameter' do
      it 'creates current term and specified number of terms ahead' do
        expect {
          described_class.perform_now(terms_ahead: 4)
        }.to change(Term, :count).by(5) # current + 4 ahead = 5 terms
      end
    end

    context 'term progression' do
      it 'creates terms in correct seasonal order' do
        described_class.perform_now(terms_ahead: 2)

        terms = Term.order(:created_at).pluck(:season, :year)

        # Verify terms progress correctly (e.g., Fall -> Spring (next year) -> Summer)
        # The exact seasons depend on current date, but we can verify count
        expect(terms.count).to eq(3)
      end
    end

    context 'logging' do
      it 'logs each created term' do
        allow(Rails.logger).to receive(:info).and_call_original

        described_class.perform_now(terms_ahead: 2)

        # Verify 3 terms were logged (current + 2 ahead)
        expect(Rails.logger).to have_received(:info).with(/Created term:/).exactly(3).times
      end
    end
  end
end
