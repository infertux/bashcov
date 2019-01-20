# frozen_string_literal: true

require "spec_helper"

RSpec.shared_examples "a silent SimpleCov loader" do |method, iterations = 3|
  before(:each) do
    raise NoMethodError, "You must define `simplecov_loader'" unless respond_to?(:simplecov_loader)
  end

  around(:each) do |example|
    saved_verbose, $VERBOSE = $VERBOSE, true
    example.run
    $VERBOSE = saved_verbose
  end

  it "silences warnings" do
    expect(simplecov_loader).to receive(:load).exactly(iterations).times.with("simplecov.rb")
    expect { iterations.times { simplecov_loader.public_send(method) } }.not_to output.to_stderr
  end
end

describe Bashcov::SimpleCovLoader do
  let!(:simplecov_loader) do
    mod = described_class
    Class.new { extend mod }
  end

  describe ".preconfigure_simplecov" do
    it "configures SimpleCov" do
      simplecov_loader.safe_load_simplecov!

      expect(SimpleCov).to receive(:project_name).at_least(:once).with("runway")

      # Allow further calls to project_name, which may occur when SimpleCov's
      # defaults are loaded upon exit from the preconfigure_simplecov block
      allow(SimpleCov).to receive(:project_name).and_call_original

      simplecov_loader.preconfigure_simplecov do
        project_name "runway"
      end
    end

    it "returns without yielding if no block was provided" do
      expect(SimpleCov).not_to receive(:configure)

      # No LocalJumpError
      expect { simplecov_loader.preconfigure_simplecov }.not_to raise_error
    end
  end

  describe ".simplecov_no_defaults" do
    it "yields to the provided block" do
      expect(ENV).to receive(:[]).with("SIMPLECOV_NO_DEFAULTS")
      expect { |b| simplecov_loader.simplecov_no_defaults(&b) }.to yield_control.once
    end

    it "returns without yielding if no block was provided" do
      expect(ENV).not_to receive(:[])

      # No LocalJumpError
      expect { simplecov_loader.simplecov_no_defaults }.not_to raise_error
    end
  end

  describe ".safe_load_simplecov!" do
    it_behaves_like "a silent SimpleCov loader", :safe_load_simplecov!
  end

  describe ".load_simplecov!" do
    it_behaves_like "a silent SimpleCov loader", :load_simplecov!
  end
end
