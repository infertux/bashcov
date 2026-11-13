# frozen_string_literal: true

require "spec_helper"
require "benchmark"

describe Bashcov::HitRelocator do
  # @param [Array<Integer, nil>] coverage hits by line, the first line first
  # @return [Array(Array, Array)] coverage, and reached lines (1-based)
  def relocate(script, coverage, subshell_hits, deparsed: true)
    lines = script.lines
    relocator = described_class.new(lines, Bashcov::Scanner.new(script).groups, deparsed:)
    zero_based = subshell_hits.transform_keys do |lineno, command, stale, holders, function|
      [lineno - 1, command, stale || false, Array(holders || [nil]).map { |holder| holder&.pred }, function]
    end
    relocated, reached = relocator.relocate(coverage, zero_based)

    [relocated, reached.map(&:succ).sort]
  end

  # @return [Hash{Integer => Integer}] hits by line (1-based)
  def hits(coverage)
    coverage.each_with_index.filter_map { |hit, index| [index + 1, hit] if hit }.to_h
  end

  let(:script) do
    <<~BASH
      out=$(
        if [ -n "$HOME" ]; then
          echo set
        else
          echo unset
        fi
        for i in 1 2; do
          echo "$i"
        done
        echo last
      )
      echo after
    BASH
  end

  # hits by line (1-based) as Bash 5.2 traces them: from the line of the
  # command holding the substitution, one command per line
  let(:traced) do
    {
      [11, '[ -n "$HOME" ]'] => 1,
      [12, "echo set"] => 1,
      # the header of the loop comes with the command which holds the
      # substitution, then with the last command of the loop
      [16, 'out=$(if [ -n "$HOME" ]; then'] => 1,
      [16, 'echo "$i"', true] => 1,
      [18, 'echo "$i"'] => 2,
      [20, "echo last"] => 1,
    }
  end

  let(:coverage) do
    Array.new(20).tap do |lines|
      lines[11 - 1] = 2 # the hit of `out=$(…)` itself
      lines[12 - 1] = 2 # the hit of `echo after`
      lines[16 - 1] = 2
      lines[18 - 1] = 2
      lines[20 - 1] = 1
    end
  end

  it "moves the hits of the commands of a substitution back to their lines" do
    relocated, = relocate(script, coverage, traced)

    expect(hits(relocated)).to eq(2 => 1, 3 => 1, 7 => 2, 8 => 2, 10 => 1, 11 => 1, 12 => 1)
  end

  it "tells which commands of a substitution got hits" do
    _, reached = relocate(script, coverage, traced)

    expect(reached).to eq [2, 3, 7, 8, 10]
  end

  it "moves hits which Bash traces from the lines as written, as before Bash 5.2" do
    # older versions trace each command as many lines after the last line of
    # the command holding the substitution as it is after its first one, less
    # one, and keep that command as written, so its first line is all that
    # comes with the header
    shifted = {
      [12, '[ -n "$HOME" ]'] => 1,
      [13, "echo set"] => 1,
      [17, "out=$("] => 1,
      [17, 'echo "$i"', true] => 1,
      [18, 'echo "$i"'] => 2,
      [20, "echo last"] => 1,
    }
    coverage = Array.new(20).tap do |lines|
      lines[11 - 1] = 1
      lines[12 - 1] = 2
      lines[13 - 1] = 1
      lines[17 - 1] = 2
      lines[18 - 1] = 2
      lines[20 - 1] = 1
    end

    relocated, = relocate(script, coverage, shifted, deparsed: false)

    expect(hits(relocated)).to eq(2 => 1, 3 => 1, 7 => 2, 8 => 2, 10 => 1, 11 => 1, 12 => 1)
  end

  it "keeps a hit whose command matches no command of the substitution" do
    relocated, reached = relocate(script, Array.new(10) + [1, 1], { [12, "echo after"] => 1 })

    expect([hits(relocated), reached]).to eq [{ 11 => 1, 12 => 1 }, []]
  end

  it "keeps a hit traced on a later command which matches" do
    script = <<~BASH
      x=$(
        echo a
      )
      (echo a)
    BASH

    relocated, = relocate(script, [nil, nil, 2, 1], { [3, "echo a"] => 1, [4, "echo a"] => 1 })

    expect(hits(relocated)).to eq(2 => 1, 3 => 1, 4 => 1)
  end

  it "tells apart the commands of nested substitutions" do
    script = <<~BASH
      x=$(
        echo a
        y=$(
          echo b
          echo c
        )
        echo d
      )
    BASH
    # the inner substitution is traced from the line of the command which
    # holds it, as Bash rebuilt the outer one
    traced = { [8, "echo a"] => 1, [10, "echo b"] => 1, [11, "echo c"] => 1, [10, "y=$(echo b"] => 1, [11, "echo d"] => 1 }

    relocated, = relocate(script, Array.new(7) + [2, nil, 2, 2], traced)

    expect(hits(relocated)).to eq(2 => 1, 3 => 1, 4 => 1, 5 => 1, 7 => 1, 8 => 1)
  end

  it "keeps a command starting like the command which holds the substitution for its own line" do
    script = <<~'BASH'
      echo \
        "$(
        true
        echo before
        for i in 1; do :; done
      )"
    BASH
    traced = { [6, "true"] => 1, [7, "echo before"] => 1, [8, "echo before", true] => 1, [10, ":"] => 1 }

    relocated, = relocate(script, [nil, nil, nil, nil, nil, 2, 1, 1, nil, 1], traced)

    expect(hits(relocated)).to eq(3 => 1, 4 => 1, 5 => 2, 6 => 1)
  end

  it "does not move a hit to a comment" do
    script = <<~BASH
      x=$(
        # echo foo
        echo foo
      )
    BASH

    relocated, = relocate(script, [nil, nil, nil, 2], { [4, "echo foo"] => 1 })

    expect(hits(relocated)).to eq(3 => 1, 4 => 1)
  end

  it "keeps a quoted # spanning lines in the text of a command" do
    script = <<~BASH
      x=$(
        echo "before # literal
      second line"
        echo done
      )
    BASH

    relocated, = relocate(script, [nil, nil, nil, nil, 1, 1, 1], { [6, 'echo "before # literal', false, 5] => 1, [7, "echo done", false, 5] => 1 })

    expect(hits(relocated)).to eq(2 => 1, 4 => 1, 5 => 1)
  end

  it "matches the quoted strings which Bash rewrites" do
    script = <<~'BASH'
      x=$(
        echo $'it\'s # literal'
        echo $"loc"
        echo done
      )
    BASH
    traced = { [5, "echo 'it'\\''s # literal'", false, 5] => 1, [6, 'echo "loc"', false, 5] => 1, [7, "echo done", false, 5] => 1 }

    relocated, = relocate(script, [nil, nil, nil, nil, 2, 1, 1], traced)

    expect(hits(relocated)).to eq(2 => 1, 3 => 1, 4 => 1, 5 => 1)
  end

  it "moves the expressions of an arithmetic for header to it, as Bash 5.3 traces them" do
    script = <<~BASH
      x=$(
        for ((i=0; i<1; i++)); do
          echo yes
        done
      )
    BASH
    traced = { [5, "((i=0))"] => 1, [5, "((i<1))"] => 2, [6, "((i++))"] => 1, [7, "echo yes"] => 1 }

    relocated, = relocate(script, [nil, nil, nil, nil, 4, 1, 1], traced)

    expect(hits(relocated)).to eq(2 => 4, 3 => 1, 5 => 1)
  end

  it "does not tell which commands ran when substitutions of the same command share a command" do
    script = <<~BASH
      printf '%s\n' "$(
        true
        echo same
      )" "$(
        if false; then
          echo same
        fi
      )"
    BASH
    # both substitutions are traced from the line of the command
    traced = { [1, "true", false, 1] => 1, [1, "false", false, 1] => 1, [2, "echo same", false, 1] => 1 }

    _, reached = relocate(script, [3, 1], traced)

    expect(reached).to eq []
  end

  it "does not tell which commands ran when a hit of the substitution matches none" do
    script = <<~BASH
      x=$(
        echo a
        echo b
      )
    BASH

    _, reached = relocate(script, [nil, nil, nil, 1, 1], { [4, "echo a", false, 4] => 1, [5, "printf b", false, 4] => 1 })

    expect(reached).to eq []
  end

  it "places a leading case header first, before the arms" do
    script = <<~BASH
      x=$(
        case x in
          y) echo same ;;
          x) echo same ;;
        esac
      )
    BASH
    # the header comes with the command which holds the substitution
    traced = { [6, "x=$(case x in ", false, 6] => 1, [11, "echo same", false, 6] => 1 }

    relocated, = relocate(script, Array.new(5) + [2, nil, nil, nil, nil, 1], traced)

    expect(hits(relocated)).to eq(2 => 1, 4 => 1, 6 => 1)
  end

  it "moves the omitted expressions of an arithmetic for header to it" do
    script = <<~BASH
      x=$(
        for ((; i<1; )); do
          echo yes
          break
        done
      )
    BASH
    traced = { [6, "((1))"] => 1, [6, "((i<1))"] => 1, [8, "echo yes"] => 1, [9, "break"] => 1 }

    relocated, = relocate(script, Array.new(5) + [3, nil, 1, 1], traced)

    expect(hits(relocated)).to eq(2 => 2, 3 => 1, 4 => 1, 6 => 1)
  end

  it "decodes the byte escapes of an ANSI-C quoted string together" do
    default_external = Encoding.default_external
    Encoding.default_external = Encoding::UTF_8
    script = <<~'BASH'
      x=$(
        printf '%s' $'\xc3\xa9'
        echo done
      )
    BASH

    relocated, = relocate(script, [nil, nil, nil, 2, 1], { [4, "printf '%s' '\u00e9'", false, 4] => 1, [5, "echo done", false, 4] => 1 })

    expect(hits(relocated)).to eq(2 => 1, 3 => 1, 4 => 1)
  ensure
    Encoding.default_external = default_external
  end

  it "keeps a hit with the substitution it was traced in" do
    script = <<~BASH
      x=$(
        true
        echo same
      )
      y=$(
        echo same
      )
    BASH
    # the first `echo same` is traced on the first line of the second
    # substitution, but before the command holding the first one
    traced = { [4, "true", false, 4] => 1, [5, "echo same", false, 4] => 1, [7, "echo same", false, 7] => 1 }

    relocated, = relocate(script, [nil, nil, nil, 2, 1, nil, 2], traced)

    expect(hits(relocated)).to eq(2 => 1, 3 => 1, 4 => 1, 6 => 1, 7 => 1)
  end

  it "keeps a hit held by a command out of any substitution where it was traced" do
    script = <<~BASH
      x=$(
        if false; then
          echo same
        fi
        echo yes
      )
      (
        echo same
      )
      echo done
    BASH
    # the subshell is no substitution: its command is traced on its own line
    traced = { [6, "false", false, 6] => 1, [9, "echo yes", false, 6] => 1, [8, "echo same", false, 10] => 1 }

    relocated, = relocate(script, [nil, nil, nil, nil, nil, 2, nil, 1, 1, 1], traced)

    expect(hits(relocated)).to eq(2 => 1, 5 => 1, 6 => 1, 8 => 1, 10 => 1)
  end

  it "does not tell which commands ran when a nested substitution shares a command with the outer one" do
    script = <<~BASH
      x=$(
        true
        y=$(
          if false; then
            echo same
          fi
          echo yes
        )
        echo same
      )
    BASH
    traced = {
      [10, "true", false, 10] => 1, [14, "y=$(if false; then", false, 10] => 1, [15, "echo same", false, 10] => 1,
      [14, "false", false, [14, 10]] => 1, [17, "echo yes", false, [14, 10]] => 1,
    }

    _, reached = relocate(script, Array.new(9) + [2, nil, nil, nil, 2, 1, nil, 1], traced)

    expect(reached).to eq []
  end

  it "counts the lines of a substitution as written, before Bash 5.2" do
    script = <<~BASH
      x=$(
        if true; then
          # comment one
          # comment two
          # comment three
          echo same
        else
          echo same
        fi
      )
    BASH
    # Bash 4.4 to 5.1 trace each command as many lines after the last line
    # of the command as it is after its first one, less one
    traced = { [11, "true", false, 10] => 1, [15, "echo same", false, 10] => 1 }

    relocated, = relocate(script, Array.new(9) + [1, 1, nil, nil, nil, 1], traced, deparsed: false)

    expect(hits(relocated)).to eq(2 => 1, 6 => 1, 10 => 1)
  end

  it "leaves the commands of a function defined out of a substitution on their own lines" do
    script = <<~BASH
      f() {
        x=$(
          if false; then
            echo same
          fi
          g
        )
      }
      g() {
        echo same
      }
      f
    BASH
    traced = { [7, "false", false, 7] => 1, [10, "g", false, 7] => 1, [10, "echo same", false, 7, "g"] => 1 }

    relocated, reached = relocate(script, [nil, nil, nil, nil, nil, nil, 2, nil, nil, 2, nil, 1], traced)

    expect([hits(relocated), reached]).to eq [{ 3 => 1, 6 => 1, 7 => 1, 10 => 1, 12 => 1 }, [3, 6]]
  end

  it "does not tell which commands ran when a function defined in a substitution ran" do
    script = <<~BASH
      x=$(
        helper() {
          echo yes
        }
        helper
        echo done
      )
    BASH
    traced = { [11, "helper", false, 7] => 1, [12, "echo done", false, 7] => 1, [9, "echo yes", false, 7, "helper"] => 1 }

    relocated, reached = relocate(script, [nil, nil, nil, nil, nil, nil, 1, nil, 1, nil, 1, 1], traced)

    expect([hits(relocated), reached]).to eq [{ 5 => 1, 6 => 1, 7 => 1, 9 => 1 }, []]
  end

  it "does not tell apart commands which share a text when Bash keeps the lines of a heredoc" do
    script = <<~BASH
      x=$(
        if true; then
          cat <<EOT
      one
      two
      three
      four
      EOT
          echo same
        else
          echo same
        fi
      )
    BASH
    traced = { [13, "true", false, 13] => 1, [14, "cat <<EOT", false, 13] => 1, [21, "echo same", false, 13] => 1 }

    _, reached = relocate(script, Array.new(12) + [2, 1, nil, nil, nil, nil, nil, nil, 1], traced)

    expect(reached).to eq []
  end

  it "finds the definition of a function whose name is joined to its parentheses by a backslash" do
    script = <<~'BASH'
      x=$(
        helper \
        () {
          echo yes
        }
        helper
        echo done
      )
    BASH
    traced = { [12, "helper", false, 8] => 1, [13, "echo done", false, 8] => 1, [10, "echo yes", false, 8, "helper"] => 1 }

    _, reached = relocate(script, Array.new(7) + [1, nil, 1, nil, 1, 1], traced)

    expect(reached).to eq []
  end

  it "finds the definition of a function whose name is split by a continuation" do
    script = <<~'BASH'
      x=$(
        hel\
      per() {
          echo yes
        }
        helper
        echo done
      )
    BASH
    traced = { [12, "helper", false, 8] => 1, [13, "echo done", false, 8] => 1, [10, "echo yes", false, 8, "helper"] => 1 }

    _, reached = relocate(script, Array.new(7) + [1, nil, 1, nil, 1, 1], traced, deparsed: false)

    expect(reached).to eq []
  end

  it "does not match a command with words in a quoted string" do
    script = <<~'BASH'
      x=$(
        if false; then
          printf '%s\n' 'if false; then echo same; fi'
        fi
        echo same
      )
    BASH

    relocated, = relocate(script, [nil, nil, nil, nil, nil, 2, nil, nil, 1], { [6, "false", false, 6] => 1, [9, "echo same", false, 6] => 1 })

    expect(hits(relocated)).to eq(2 => 1, 5 => 1, 6 => 1)
  end

  it "matches a command in a substitution in a quoted string" do
    script = <<~BASH
      x=$(
        y="$(echo one)"
        echo "a $(echo two) b"
      )
    BASH
    traced = {
      [4, 'y="$(echo one)"', false, 4] => 1, [4, "echo one", false, [4, 4]] => 1,
      [5, 'echo "a $(echo two) b"', false, 4] => 1, [5, "echo two", false, [5, 4]] => 1,
    }

    _, reached = relocate(script, [nil, nil, nil, 3, 2], traced)

    expect(reached).to eq [2, 3]
  end

  it "places the hits of a nested substitution with the outer command holding it" do
    script = <<~BASH
      x=$(
        :
        y=$(
          echo yes
        )
      )
      z=$(
        if false; then
          echo yes
        fi
      )
    BASH
    # the line of `y=$(…)` is one Bash made up, in the lines of `z=$(…)`
    traced = {
      [6, ":", false, 6] => 1, [7, "y=$(echo yes)", false, 6] => 1, [7, "echo yes", false, [7, 6]] => 1,
      [11, "false", false, 11] => 1,
    }

    relocated, = relocate(script, [nil, nil, nil, nil, nil, 2, 2, nil, nil, nil, 2], traced)

    expect(hits(relocated)).to eq(2 => 1, 3 => 1, 4 => 1, 6 => 1, 8 => 1, 11 => 1)
  end

  it "does not tell apart commands which share a text after a compound command on one line" do
    script = <<~BASH
      x=$(
        if true; then echo yes; else :; fi
        if true; then
          echo same
        else
          echo same
        fi
      )
    BASH
    traced = { [8, "true", false, 8] => 1, [9, "echo yes", false, 8] => 1, [13, "true", false, 8] => 1, [14, "echo same", false, 8] => 1 }

    _, reached = relocate(script, Array.new(7) + [2, 1, nil, nil, nil, 1, 1], traced)

    expect(reached).to eq []
  end

  it "keeps a hit on a line out of the substitution which holds its command" do
    script = <<~BASH
      main() {
        x=$(
          if false; then
            echo same
          fi
          echo yes
        )
      }
      background() {
        echo same
      }
      background &
      main
    BASH
    # the background job traces its commands among those of the substitution
    traced = { [8, "false", false, 7] => 1, [10, "echo same", false, 7] => 1, [11, "echo yes", false, 7] => 1 }

    relocated, reached = relocate(script, Array.new(6) + [1, 1, nil, 1, 1, 1, 1], traced)

    expect([hits(relocated)[10], reached]).to eq [1, []]
  end

  it "ends an ANSI-C quoted string at its first NUL, as Bash does" do
    script = <<~'BASH'
      x=$(
        echo 'foo'
        echo $'foo\0bar'
      )
    BASH

    relocated, = relocate(script, [nil, nil, nil, 2, 1], { [4, "echo 'foo'", false, 4] => 1, [5, "echo 'foo'", false, 4] => 1 })

    expect(hits(relocated)).to eq(2 => 1, 3 => 1, 4 => 1)
  end

  it "reads a control escape of an ANSI-C quoted string as its character, a NUL for one" do
    script = <<~'BASH'
      x=$(
        echo 'foo'
        echo $'foo\c@bar'
      )
    BASH

    relocated, = relocate(script, [nil, nil, nil, 2, 1], { [4, "echo 'foo'", false, 4] => 1, [5, "echo 'foo'", false, 4] => 1 })

    expect(hits(relocated)).to eq(2 => 1, 3 => 1, 4 => 1)
  end

  it "matches the duplication of a file descriptor, which Bash traces with the descriptor it sets" do
    script = <<~BASH
      x=$(
        echo ok
        echo warn >&2
        if false; then
          echo never
        fi
      )
    BASH
    traced = { [7, "echo ok", false, 7] => 1, [8, "echo warn 1>&2", false, 7] => 1, [9, "false", false, 7] => 1 }

    relocated, reached = relocate(script, Array.new(6) + [2, 1, 1], traced)

    expect([hits(relocated), reached]).to eq [{ 2 => 1, 3 => 1, 4 => 1, 7 => 1 }, [2, 3, 4]]
  end

  it "keeps a hit on the last line of a command spanning lines out of the substitution" do
    script = <<~BASH
      main() {
        x=$(
          if false; then
            printf 'one
      two'
          fi
          echo yes
        )
      }
      background() {
        printf 'one
      two'
      }
      background &
      main
    BASH
    # before Bash 5.3, the command of the background job is traced on its last line
    traced = { [9, "false", false, 8] => 1, [12, "printf 'one", false, 8] => 1, [10, "echo yes", false, 8] => 1 }

    relocated, reached = relocate(script, Array.new(7) + [1, 1, 1, nil, 1], traced)

    expect([hits(relocated)[12], reached]).to eq [1, []]
  end

  it "does not guess where hits go when each of them matches several commands" do
    script = <<~BASH
      x=$(
        if false; then
          false
        else
          false
        fi
      )
    BASH

    _, reached = relocate(script, Array.new(6) + [2, nil, nil, 1], { [7, "false", false, 7] => 1, [10, "false", false, 7] => 1 })

    expect(reached).to eq []
  end

  it "places a hit which its command held past the lines where hits are looked for" do
    script = <<~BASH
      x=$(
        case x in a) :;; b) :;; c) :;; d) :;; e) :;; f) :;; x) :;; esac
        echo done
      )
    BASH
    # Bash rebuilds each clause of the case command on lines of its own
    traced = { [4, "x=$(case x in ", false, 4] => 1, [24, ":", false, 4] => 1, [27, "echo done", false, 4] => 1 }

    relocated, reached = relocate(script, Array.new(3) + [2] + Array.new(19) + [1, nil, nil, 1], traced)

    expect([hits(relocated), reached]).to eq [{ 2 => 2, 3 => 1, 4 => 1 }, [2, 3]]
  end

  it "places the hits of a nested substitution held past the lines where hits are looked for" do
    script = <<~BASH
      x=$(
        case x in 0) :;; 1) :;; 2) :;; 3) :;; 4) :;; 5) :;; 6) :;; 7) :;; 8) :;; x) :;; esac
        y=$(
          echo yes
        )
      )
    BASH
    traced = {
      [6, "x=$(case x in ", false, 6] => 1, [35, ":", false, 6] => 1, [38, "y=$(echo yes)", false, 6] => 1,
      [38, "echo yes", false, [38, 6]] => 1,
    }

    relocated, reached = relocate(script, Array.new(5) + [2] + Array.new(28) + [1, nil, nil, 2], traced)

    expect([hits(relocated), reached]).to eq [{ 2 => 2, 3 => 1, 4 => 1, 6 => 1 }, [2, 3, 4]]
  end

  it "keeps the hits of a command holding a substitution which ran in another process" do
    script = <<~BASH
      main() {
        x=$(
          if false; then
            value=$(
              echo yes
            )
          fi
          echo done
        )
      }
      (
        value=$(
          echo yes
        )
      ) &
      main
    BASH
    # the background job traces its commands among those of the substitution
    traced = {
      [10, "false", false, 9] => 1, [14, "echo yes", false, [14, 9]] => 1, [14, "value=$(echo yes)", false, 9] => 1,
      [13, "echo done", false, 9] => 1,
    }

    relocated, reached = relocate(script, Array.new(8) + [1, 1, nil, nil, 1, 2], traced)

    expect([hits(relocated)[14], reached]).to eq [2, []]
  end

  it "keeps a # in a string quoted inside a substitution which is itself in quotes" do
    script = <<~BASH
      x=$(
        echo "$(printf '%s' " # literal")"
        if false; then
          echo never
        fi
      )
    BASH
    traced = {
      [6, %q(echo "$(printf '%s' " # literal")"), false, 6] => 1, [6, %q(printf '%s' " # literal"), false, [6, 6]] => 1,
      [7, "false", false, 6] => 1,
    }

    relocated, reached = relocate(script, Array.new(5) + [3, 1], traced)

    expect([hits(relocated), reached]).to eq [{ 2 => 2, 3 => 1, 6 => 1 }, [2, 3]]
  end

  it "joins the parts of a word which a line continuation splits" do
    script = "x=$(\n  echo hel\\\nlo\n  if false; then\n    echo never\n  fi\n)\n"
    traced = { [7, "echo hello", false, 7] => 1, [8, "false", false, 7] => 1 }

    relocated, reached = relocate(script, Array.new(6) + [2, 1], traced)

    expect([hits(relocated), reached]).to eq [{ 2 => 1, 4 => 1, 7 => 1 }, [2, 4]]
  end

  it "scans long quoted strings in linear time" do
    script = "x=$(\n  : '#{'é' * 64_000}'\n  : done\n)\n"
    elapsed = Benchmark.realtime do
      relocate(script, [nil, nil, nil, 2], { [4, ": '#{'é' * 64_000}'", false, 4] => 1, [5, ": done", false, 4] => 1 })
    end

    expect(elapsed).to be < 2
  end

  it "keeps a command run again apart from a loop header" do
    script = <<~BASH
      x=$(
        echo a
        echo a
        for i in 1 2; do
          echo b
        done
      )
    BASH
    traced = {
      [7, "echo a", false, 7] => 1, [8, "echo a", false, 7] => 1, [9, "echo a", true, 7] => 1,
      [9, "echo b", true, 7] => 1, [11, "echo b", false, 7] => 2,
    }

    relocated, = relocate(script, Array.new(6) + [2, 1, 2, nil, 2], traced)

    expect(hits(relocated)).to eq(2 => 1, 3 => 1, 4 => 2, 5 => 2, 7 => 1)
  end

  context "with identical commands in both branches of a condition" do
    def branch_hits(condition, traced)
      script = <<~BASH
        x=$(
          if #{condition}; then
            echo same
          else
            echo same
          fi
        )
        echo "$x"
      BASH
      coverage = Array.new(10).tap { |lines| traced.each_key { |lineno, _| lines[lineno - 1] = 1 } }
      coverage[7 - 1] = coverage[7 - 1].to_i + 1 # the hit of `x=$(…)` itself
      coverage[8 - 1] = coverage[8 - 1].to_i + 1 # the hit of `echo "$x"`

      hits(relocate(script, coverage, traced).first)
    end

    it "moves the hit to the branch which ran when the condition holds" do
      expect(branch_hits("true", { [7, "true"] => 1, [8, "echo same"] => 1 })).to eq(2 => 1, 3 => 1, 7 => 1, 8 => 1)
    end

    it "moves the hit to the branch which ran when the condition fails" do
      expect(branch_hits("false", { [7, "false"] => 1, [10, "echo same"] => 1 })).to eq(2 => 1, 5 => 1, 7 => 1, 8 => 1)
    end
  end

  it "aligns many identical commands in order" do
    script = "x=$(\n#{"  echo same\n" * 300})\n"
    traced = (1..300).to_h { |index| [[301 + index, "echo same", false, 302], 1] }

    relocated, = relocate(script, Array.new(301) + [2] + Array.new(299, 1), traced)

    expect(hits(relocated)).to eq((2..301).to_h { |lineno| [lineno, 1] }.merge(302 => 1))
  end

  it "keeps the order of identical commands" do
    script = <<~BASH
      x=$(echo a
        echo a
        echo a)
    BASH

    relocated, = relocate(script, [nil, nil, 2, 1, 1], { [3, "echo a"] => 1, [4, "echo a"] => 1, [5, "echo a"] => 1 })

    expect(hits(relocated)).to eq(1 => 1, 2 => 1, 3 => 2)
  end
end
