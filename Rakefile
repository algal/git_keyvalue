require "bundler/gem_tasks"

require "yard"
require "redcarpet" # needed for yard's markdown processing (?)

YARD::Rake::YardocTask.new do |t|
  t.files = ['lib/**/*.rb']
  t.options = ['--output-dir', 'doc/lib/']
end
