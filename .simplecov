# frozen_string_literal: true

SimpleCov.start do
  minimum_coverage 95
  add_filter "/features/"
  add_filter "/spec/"
  add_filter "/tmp/"
  add_filter "/.git/"
end
