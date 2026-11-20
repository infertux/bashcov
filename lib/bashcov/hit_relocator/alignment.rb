# frozen_string_literal: true

module Bashcov
  class HitRelocator
    # Penalty for placing a hit outside the ranks allowed by its anchors.
    OUT_OF_BOUNDS = 1_000

    # Most pairs of hits and candidates to weigh for a command text, which
    # takes about half a second: past it, its hits stay where Bash traced
    # them and the placement is unsure.
    MAX_PAIRS = 1_000_000

    # Matches traced occurrences of the same command to source lines in order.
    # Anchors are [trace line, source rank] pairs from known header positions
    # or command text with only one possible source. All lines are zero-based.
    module Alignment
    module_function

      # Each group pairs sorted [line, count, text] hits with their candidates.
      # Returns [placements, certain]. Without anchors, duplicate candidates
      # can still receive hits, but their unhit siblings may also have run.
      def place(groups, leading)
        oversized, groups = groups.partition { |hits, candidates| oversized?(hits, candidates) }
        return [[], oversized.empty?] if groups.empty?

        anchors = groups.select { |_, candidates| candidates.one? }.flat_map do |hits, (candidate)|
          hits.map { |lineno, _| [lineno, candidate.rank] }
        end
        anchors = (anchors + leading).sort
        certain = !anchors.empty? || groups.none? { |_, candidates| candidates.size > 1 }
        anchors = [[groups.map { |hits, _| hits.first.first }.min, 0]] if anchors.empty?

        placed = groups.flat_map do |hits, candidates|
          next [] if candidates.empty?

          hits.zip(targets(hits, candidates, anchors)).map do |(lineno, count, _), candidate|
            [lineno, count, candidate.lineno]
          end
        end
        [placed, certain && oversized.empty?]
      end

      # @return [Boolean] whether placing +hits+ on +candidates+ takes
      #   weighing more than {MAX_PAIRS} pairs of them, see {.targets}
      def oversized?(hits, candidates)
        candidates.size > 1 && hits.size != candidates.size && hits.size * candidates.size > MAX_PAIRS
      end

      # Expect one command per traced line, measured from the preceding
      # anchor (or the first one). Prefer ranks between neighboring anchors.
      def expected_rank(anchors, lineno)
        index = anchors.bsearch_index { |line, _| line > lineno } || anchors.size
        before = anchors[index - 1] if index.positive?
        after = anchors[index]
        line, rank = before || anchors.first
        lowest = before ? before.last : 0
        highest = after ? after.last - 1 : Float::INFINITY
        [rank + (lineno - line), lowest..highest]
      end

      def targets(hits, candidates, anchors)
        return Array.new(hits.size, candidates.first) if candidates.one?
        # Equal lengths permit only one strictly increasing assignment.
        return candidates if hits.size == candidates.size

        distances = hits.map do |lineno, _|
          rank, bounds = expected_rank(anchors, lineno)
          candidates.map { |candidate| (rank - candidate.rank).abs + (bounds.cover?(candidate.rank) ? 0 : OUT_OF_BOUNDS) }
        end
        indices = cheapest_alignment(distances, hits.size > candidates.size)
        indices.map { |index| candidates[index] }
      end

      # @param [Array<Array<Integer>>] distances distance between each hit and
      #   each candidate
      # @param [Boolean] shared whether several hits may go to the same
      #   candidate, when there are more hits than candidates
      # @return [Array<Integer>] for each hit, the index of its candidate, in
      #   increasing order, which minimizes the sum of the distances
      def cheapest_alignment(distances, shared)
        # for each candidate, the lowest cost of placing the hits read so far
        # with the last one on it, and the candidates of these hits, the last
        # one first, as a linked list
        costs = distances.first.each_with_index.map { |distance, candidate| [distance, [candidate, nil]] }
        distances.drop(1).each do |row|
          before = costs
          lowest = nil
          costs = row.each_with_index.map do |distance, candidate|
            reachable = shared ? before[candidate] : (before[candidate - 1] if candidate.positive?)
            lowest = reachable if reachable && (lowest.nil? || reachable.first < lowest.first)
            [lowest.first + distance, [candidate, lowest.last]] if lowest
          end
        end

        path = costs.compact.min_by(&:first).last
        indices = []
        while path
          candidate, path = path
          indices << candidate
        end
        indices.reverse
      end

      private_class_method :oversized?, :expected_rank, :targets, :cheapest_alignment
    end
  end
end
