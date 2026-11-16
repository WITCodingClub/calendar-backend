# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "finals rake tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:status) { instance_double(Process::Status, success?: true) }
  let(:pdf_text) { file_fixture("finals_schedules/spring_2026.txt").read }

  before do
    allow(Open3).to receive(:capture3).with("pdftotext", "-layout", anything, "-").and_return([ pdf_text, "", status ])
  end

  around do |example|
    keys  = %w[DIR]
    saved = keys.to_h { |key| [ key, ENV.fetch(key, nil) ] }
    keys.each { |key| ENV.delete(key) }
    example.run
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def run_task(name, env = {})
    env.each { |key, value| ENV[key] = value }
    task = Rake::Task[name]
    task.reenable
    original = $stdout
    $stdout = StringIO.new
    task.invoke
    $stdout.string
  ensure
    $stdout = original
  end

  describe "finals:check_corpus" do
    it "prints counts and warnings for each PDF in DIR" do
      Dir.mktmpdir do |dir|
        File.binwrite(File.join(dir, "spring.pdf"), "%PDF-1.4")
        allow(Open3).to receive(:capture3).with("pdftotext", "-layout", anything, "-")
          .and_return([ "#{pdf_text}ZQXA1000-01   10001   after lunch\n", "", status ])

        output = run_task("finals:check_corpus", "DIR" => dir)

        expect(output).to include("spring.pdf: 2 CRNs, 0 combined, 0 with no room, 1 warnings", "Row has no exam date and time")
      end
    end
  end
end
