# Real pinned Fastlane parser, synthetic credentials only; no Runner/network/Apple.
require "stringio"
require "tmpdir"
require "fileutils"
ENV["FASTLANE_SKIP_UPDATE_CHECK"] = "1"
ENV["FASTLANE_OPT_OUT_USAGE"] = "1"
require "fastlane"
require "deliver"

def capture_output
  previous = $stdout
  output = StringIO.new
  $stdout = output
  yield
  output.string
ensure
  $stdout = previous
end

def check(condition, message)
  raise message unless condition
end

email = "synthetic-review@example.invalid"
password = "synthetic-ONLY-review-secret"
ENV["X5_APP_REVIEW_EMAIL"] = email
ENV["X5_APP_REVIEW_PASSWORD"] = password
repo = File.expand_path("..", __dir__)

# Reproduce the unsafe DSL with the actual dependency; don't emit its output.
Dir.mktmpdir("x5-review-parser-") do |directory|
  File.write(File.join(directory, "Deliverfile"), "app_review_information({demo_user: '#{email}', demo_password: '#{password}'})\n")
  Dir.chdir(directory) do
    unsafe = FastlaneCore::Configuration.create(Deliver::Options.available_options, {})
    emitted = capture_output { unsafe.load_configuration_file("Deliverfile") }
    check(emitted.include?(password), "Unsafe DSL counterexample was not reproduced")
  end
end

Dir.chdir(repo) do
  configured = FastlaneCore::Configuration.create(Deliver::Options.available_options, {})
  emitted = capture_output do
    configured.load_configuration_file("Deliverfile")
    FastlaneCore::PrintTable.print_values(config: configured,
      mask_keys: ["app_review_information.demo_password"], title: "Synthetic Runner Summary")
  end
  actual = configured[:app_review_information]
  check(actual[:demo_user] == email && actual[:demo_password] == password, "Required credential pair changed")
  check(!emitted.include?(email) && !emitted.include?(password), "Fixed configuration leaked synthetic credentials")

  ENV.delete("X5_APP_REVIEW_PASSWORD")
  rejected = false
  emitted = capture_output do
    begin
      FastlaneCore::Configuration.create(Deliver::Options.available_options, {}).load_configuration_file("Deliverfile")
    rescue StandardError => error
      rejected = error.message.include?("Missing protected X5 App Review credentials")
    end
  end
  check(rejected, "Missing secret did not stop configuration")
  check(!emitted.include?(email) && !emitted.include?(password), "Failure path leaked synthetic credentials")
end
puts "PASS: unsafe DSL reproduced; protected config preserves both credentials without stdout; missing secret refused. No Apple request."
