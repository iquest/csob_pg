# frozen_string_literal: true

require 'minitest/test_task'

Minitest::TestTask.create(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_globs = ['test/test.rb']
  t.verbose = true
end

desc 'Run tests'
task default: :test
