shared_context "temporary script" do |script_basename|
  before(:each) do
    raise NoMethodError, "You must define `script_text'" unless respond_to?(:script_text)
  end

  let(:tmpscript) do
    script = File.open(File.join(Dir.getwd, script_basename + ".sh"), "w")
    script.write(script_text)
    script.close
    script
  end

  let(:tmprunner) { Bashcov::Runner.new("#{Bashcov.options.bash_path} #{tmpscript.path}") }

  around do |example|
    Dir.mktmpdir script_basename do |tmpdir|
      Dir.chdir tmpdir do
        example.run
      end
    end
  end
end
