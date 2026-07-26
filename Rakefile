# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new do |task|
  task.libs << "lib"
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
  task.warning = true
end

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
rescue LoadError
  desc "Install development dependencies to run RuboCop"
  task :rubocop do
    warn "RuboCop is not installed. Run bundle install first."
  end
end

task default: :test
