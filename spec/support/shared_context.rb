# frozen_string_literal: true

require "tmpdir" # Dir.mktmpdir

shared_context "with a temporary script" do |script_basename|
  before do
    raise NoMethodError, "You must define `script_text'" unless respond_to?(:script_text)
  end

  let(:tmpscript) do
    script = File.open(File.join(Dir.getwd, "#{script_basename}.sh"), "w")
    script.write(script_text)
    script.close
    script
  end

  let(:tmprunner) { Bashcov::Runner.new([Bashcov.bash_path, tmpscript.path]) }

  around do |example|
    Dir.mktmpdir script_basename do |tmpdir|
      Dir.chdir tmpdir do
        example.run
      end
    end
  end
end

shared_context "with a delimited stream" do |field_count, start = "START>"| # rubocop:disable RSpec/MultipleMemoizedHelpers
  let(:field_count) { field_count }
  let(:start) { start }
  let(:start_match) { /#{Regexp.escape(start)}$/ }
  let(:delimiter) { SecureRandom.uuid }
  let(:token_length) { 4 }
  let(:taken) { 10 }
  # @note +(taken + 1) * 2+ to account for the start-of-fields signifier and
  # for the delimiters -- i.e., if we want to yield 10 actual fields, we have
  # to take 22 from the generator because 10 of these will be +delimiter+ and
  # 2 will be +start+.
  let(:input) { generator.take((taken + 1) * 2).join }
  let(:read) { StringIO.new(input).tap(&:close_write) }
  let(:stream) { Bashcov::FieldStream.new(read) }

  # Generate a series of fields delimited by +delimiter+
  let(:generator) do
    Enumerator.new do |y|
      b = true
      fields_yielded = 0

      loop do
        if b
          y << (fields_yielded == 0 ? start : SecureRandom.base64(token_length))
          fields_yielded = (fields_yielded == field_count + 1 ? 0 : fields_yielded + 1)
        else
          y << delimiter
        end

        b ^= true
      end
    end
  end
end
