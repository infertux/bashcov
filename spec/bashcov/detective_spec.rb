# frozen_string_literal: true

require "spec_helper"

describe Bashcov::Detective do
  let(:detective) { described_class.new("bash") }

  describe "#shellscript_shebang_line?" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:whitespace)  { ["", " ", "   ", "\t"] }
    let(:bindirs)     { %w[bin usr/bin usr/local/bin].map { |d| "/#{d}/" } }
    let(:prefixes)    { [""] + bindirs }
    let(:shells)      { %w[sh bash] }
    let(:notshells)   { %w[python3 ruby emacs 1.2.3 --hmm] }
    let(:envs)        { combine(["env", "env -S"]) }
    let(:notenvs)     { combine(["false", "hello --world"]) }
    let(:valid)       { make_shebangs(shells) }
    let(:png)         { "\x89PNG\r\n" }

    let(:invalid) do
      ["", "\n", "\t\n", "foo", png] + make_shebangs(notshells) + shebangify(with_executors(combine(shells), executors: notenvs))
    end

    def combine(candidates)
      whitespace.product(prefixes).map(&:join).product(candidates).map(&:join)
    end

    def with_executors(interpreters, executors: envs)
      interpreters.flat_map { |i| executors.map { |e| [e, i].join(" ") } }
    end

    def combine_with_executors(candidates, executors: envs)
      combine(candidates).then do |base|
        base + with_executors(base, executors: executors)
      end
    end

    def shebangify(candidates)
      candidates.map { |c| "#!#{c}" }
    end

    def make_shebangs(candidates, executors: envs)
      shebangify(combine_with_executors(candidates, executors: executors))
    end

    it "returns true for shell interpreters" do
      aggregate_failures "valid shebang handling" do
        valid.each do |s|
          expect(detective.shellscript_shebang_line?(s)).to \
            be(true), "#{s.inspect} is a valid shell shebang"
        end
      end
    end

    it "returns false for non-shell interpreters" do
      aggregate_failures "invalid shebang handling" do
        invalid.each do |s|
          expect(detective.shellscript_shebang_line?(s)).to \
            be(false), "#{s.inspect} is not a valid shell shebang"
        end
      end
    end
  end

  describe "#shellscript_extension?" do
    it "returns true for filenames with shell extensions" do
      aggregate_failures "shell extension handling" do
        %w[foo.sh wa.bash].each do |filename|
          expect(detective.shellscript_extension?(filename)).to \
            be(true), "#{filename.inspect} has a shell filename extension"
        end
      end
    end

    it "returns false for filenames without shell extensions" do
      aggregate_failures "shell extension handling" do
        %w[foo.py wa.rb .sh .bash sh bash].each do |filename|
          expect(detective.shellscript_extension?(filename)).to \
            be(false), "#{filename.inspect} does not have a shell filename extension"
        end
      end
    end
  end
end
