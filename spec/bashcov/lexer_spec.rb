# frozen_string_literal: true

require "spec_helper"

describe Bashcov::Lexer do
  describe "#initialize" do
    it "raises if the file is invalid" do
      expect do
        described_class.new "inexistent_file.exe", nil
      end.to raise_error ArgumentError
    end
  end

  describe "#complete_coverage" do
    it "marks relevant lines" do
      file = "#{test_app}/scripts/nested/simple.sh"
      coverage = {}
      expected = expected_coverage.fetch(file).fetch("lines").each_with_index.map do |line, index|
        index unless line.nil?
      end.compact

      described_class.new(file, coverage).complete_coverage

      expect(coverage.keys).to match_array expected
    end

    context "with a string closed after a space" do
      # see https://github.com/infertux/bashcov/issues/118
      let(:script) do
        <<~'BASH'
          f() {
            if [ -n "$2" ]; then
              printf '%s [%s]: ' "$1" "$2" >&2
            else
              printf '%s: ' "$1" >&2
            fi
            printf '%s\n' "$1"
          }
        BASH
      end

      it "does not read the closing quote as a multiline string opener" do
        expect(complete(script, Array.new(8))).to eq [nil, 0, 0, nil, 0, nil, 0, nil]
      end

      it "does not copy hits onto lines that never ran" do
        coverage = Array.new(8).tap { |c| c[1] = c[2] = c[6] = 1 }
        expect(complete(script, coverage)).to eq [nil, 1, 1, nil, 0, nil, 1, nil]
      end
    end

    it "still matches a multiline string opened inside a command substitution" do
      script = <<~'BASH'
        sizes="$(awk -v h="${HEIGHT}" 'BEGIN {
          printf "%d\n", h * 2
        }')"
      BASH

      expect(complete(script, [1, nil, nil])).to eq [1, 1, 1]
    end

    it "matches a multiline string opened after another one closes on the same line" do
      script = <<~BASH
        echo "a
        b" && echo "c
        d" "e
        f"
        A='x
        y'; B='p
        q'
      BASH

      expect(complete(script, [1, 1, nil, nil, 1, nil, nil])).to eq [1, 1, 1, 1, 1, 1, 1]
    end

    it "matches a multiline string opened after a string holding the other quote" do
      script = <<~BASH
        printf "%s" "it's" 'first
        second'
        echo 'say "hi' "first
        second"
      BASH

      expect(complete(script, [1, nil, 1, nil])).to eq [1, 1, 1, 1]
    end

    it "matches a multiline string holding other strings in a command substitution" do
      script = <<~'BASH'
        test "" = "$(grep '^Signed-off-by: ' "$1" |
          sort | uniq -c | sed -e '/^[ 	]*1[ 	]/d')" || exit
        DIFF="$(diff -u \
          "$a" "$b" \
          "$c")" || true
      BASH

      expect(complete(script, [5, nil, nil, nil, 3])).to eq [5, 5, 3, 3, 3]
    end

    it "does not read a closing quote on its own line as a multiline string opener" do
      script = <<~'BASH'
        out=`awk '
          { print }
        	'`

        case $out in
        x)
          echo 'a' \
            'b';;
        esac
      BASH

      expect(complete(script, [nil, nil, 2, nil, 2, nil, nil, nil, nil])).to eq [2, 2, 2, nil, 2, nil, 0, 0, nil]
    end
  end

  def complete(script, coverage)
    Tempfile.create(%w[lexer .sh]) do |file|
      file.write(script)
      file.close
      described_class.new(file.path, coverage).complete_coverage
    end

    coverage
  end
end
