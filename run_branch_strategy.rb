#!/usr/bin/env ruby

require 'optparse'

options = {}

def show_strategies(options)
  puts "Strategies used:"
  options.each do |op, strategy|
    puts "  #{op}: #{strategy}"
  end
end


BRANCH_UDPATE_STRATEGIES = {
  'rebase' => -> { _ 'git rebase master' },
  'merge' => -> { _ 'git merge master' }
}

MERGE_STRATEGIES = {
  'merge' => -> branch, *args { _ "git merge #{branch}", *args },
  'squash' => -> branch, *args do
    succeeded = _ "git merge --squash #{branch}", *args
    if succeeded
      _ "git commit -m 'Squash merged #{branch}'"
    end
  end
}

opts = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} --update [update_strategy] --merge [merge_strategy]"

  opts.on("--update STRATEGY", "Strategy for updating branch. One of #{BRANCH_UDPATE_STRATEGIES.keys.join(', ')}") do |s|
    options[:update_strategy] = s
  end

  opts.on("--merge STRATEGY", "Strategy for merging to master. One of #{MERGE_STRATEGIES.keys.join(', ')}") do |s|
    options[:merge_strategy] = s
  end
end
opts
opts.parse!

if !(options[:update_strategy] && options[:merge_strategy])
  puts opts
  exit 1
end

def _(command, options = {})
  puts "  #{command}" unless options[:silent]
  output = `#{ command} 2>&1`
  result = $?.success?

  if options[:should_fail] && result
    raise %{
Expected '#{command}' to fail, but it didn't
Output:
#{output}
}.strip
  end

  if !options[:should_fail] && !result
    raise %{
'#{command}' failed
Output:
#{output}
}.strip
  end

  if options[:show_output]
    puts output
  end

  result
end

def in_dir(dir, options = {})
  if !options[:silent]
    puts
    puts "In #{dir}"
  end

  Dir.chdir(dir) do
    yield
  end
end

def run(options)
  _ 'rm -rf example', silent: true
  _ 'mkdir -p example/master', silent: true

  Dir.chdir 'example'

  in_dir 'master', silent: true do
    _ 'git init --bare .', silent: true
  end

  _ 'git clone master bob', silent: true

  in_dir 'bob' do
    puts "  Create initial config file on master"
    _ 'echo foo > config', silent: true
    _ 'git add config', silent: true
    _ 'git commit -m "Initial Commit"'
    _ 'git push origin master'

    puts "  Start bobs_branch, edit config, and push for review"
    _ 'git checkout -b bobs_branch', silent: true
    _ 'echo bar >> config', silent: true
    _ 'git add config', silent: true
    _ 'git commit -m "Added bar to config"', silent: true
    _ 'git push origin bobs_branch'
  end

  _ 'git clone master alice', silent: true

  in_dir 'alice' do
    puts "  Start alices_branch and edit config"
    _ 'git checkout -b alices_branch', silent: true
    _ 'echo baz >> config', silent: true

    _ 'git add config', silent: true
    _ 'git commit -m "Added baz to config"'

    puts "  Push our branch for review, then merge to master"
    _ 'git push origin alices_branch', silent: true
    _ 'git checkout master', silent: true
    MERGE_STRATEGIES[options[:merge_strategy]].call 'alices_branch'
    _ 'git push origin master'
  end

  in_dir 'bob' do
    puts "  Merge our branch to latest master"
    _ 'git checkout master', silent: true
    _ 'git pull', silent: true

    MERGE_STRATEGIES[options[:merge_strategy]].call 'bobs_branch', should_fail: true

    puts "  Resolve a merge conflict"
    _ 'git checkout --ours config', silent: true
    _ 'echo bar >> config', silent: true
    _ 'git add config', silent: true
    _ 'git commit -m "Merging bobs_branch (conflict resolved)"'
    _ 'git push origin master'
  end

  in_dir 'alice' do
    puts "  Add and commit new_file"
    _ 'git checkout alices_branch', silent: true
    _ 'echo foo > new_file', silent: true
    _ 'git add new_file', silent: true
    _ 'git commit -m "Adding new_file"', silent: true

    puts "  Merge latest master back to our branch"

    _ 'git checkout master', silent: true
    _ 'git pull', silent: true
    _ 'git checkout alices_branch', silent: true
    BRANCH_UDPATE_STRATEGIES[options[:update_strategy]].call

    _ 'git push origin alices_branch', silent: true

    puts "  Merge branch back to master"

    _ 'git checkout master', silent: true
    MERGE_STRATEGIES[options[:merge_strategy]].call 'alices_branch'
    _ 'git push origin master', silent: true

    puts "  Master history looks like this"
    puts ""

    _ 'git log --graph --pretty=oneline', show_output: true, silent: true
  end
end

begin
  run options
rescue => e
  puts
  puts e.message
  puts
  show_strategies options
else
  puts
  show_strategies options
end


