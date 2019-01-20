# frozen_string_literal: true

require "spec_helper"

require "simplecov/result"

require "bashcov/ext/simplecov"

describe Bashcov::Ext::SimpleCov do
  describe ".result" do
    # Calling SimpleCov.result causes SimpleCov.running to be set to false;
    # ensure that we save and restore the current SimpleCov.running.
    around(:each) do |example|
      saved_running = SimpleCov.running
      example.run
      SimpleCov.running = saved_running
      SimpleCov.clear_result
    end

    let!(:refinement_consumer) do
      # Not possible to call `using` in a method, so do it in `main` instead
      TOPLEVEL_BINDING.eval <<-CODE
        Class.new do
          using #{described_class}

          def self.simplecov_result(result = nil)
            SimpleCov.result(result)
          end
        end
      CODE
    end

    let(:result) { SimpleCov::Result.new({}) }

    context "given a SimpleCov::Result object" do
      it "permits storing that object as SimpleCov.result" do
        refinement_consumer.simplecov_result(result)
        expect(SimpleCov.result).to be result
      end
    end

    it "it sets SimpleCov.running to false" do
      SimpleCov.running = true

      # Store dummy result to avoid triggering Coverage.result, thereby
      # clobbering the running RSpec suite's coverage results
      refinement_consumer.simplecov_result(result)

      expect(SimpleCov.running).to be false
    end
  end
end
