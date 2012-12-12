require 'spec_helper'

describe Bashcov do
  describe ".link" do
    it "includes the version" do
      Bashcov.link.should include Bashcov::VERSION
    end
  end
end

