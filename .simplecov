# frozen_string_literal: true

SimpleCov.configure do
  minimum_coverage 95
  skip "/features/"
  skip "/spec/"
  skip "/tmp/"
  skip "/.git/"
end
