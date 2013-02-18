Dir["spec/models/*_spec.rb"].sort.each do |path|
  cmd = "bundle exec ruby -Ispec '#{path}'"
  puts cmd
  system cmd
end
