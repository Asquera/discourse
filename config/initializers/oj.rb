unless RUBY_PLATFORM =~ /java/
  # Not sure why it's not using this by default!
  MultiJson.engine = :oj
end
