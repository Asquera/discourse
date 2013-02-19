class ActiveRecord::Base  

  # Execute SQL manually
  def self.exec_sql(*args)
    conn = ActiveRecord::Base.connection
    sql = ActiveRecord::Base.send(:sanitize_sql_array, args)
    result = conn.execute(sql)

    if result.respond_to?(:values) # MRI Postgres adapter
      result
    else # JDBC adapters don't return PG::Result, but as mostly only #values is called, we can emulate it.
      if result.kind_of?(Array)
        result = result.dup

        def result.values
          if empty?
            self
          else
            [self.first.values.map(&:to_s)]
          end
        end

        result
      else
        result
      end
    end
  end

  def self.exec_sql_row_count(*args)
    if RUBY_PLATFORM =~ /java/
      # There's no way to get the affected row count with the JDBC
      # adapter elegantly. So fire raw SQL to get the row count;
      # the NOTICE is cought by the JDBC adapter and we get a nice
      # integer back.

      conn = ActiveRecord::Base.connection
      sql = <<-SQL
DO $$
DECLARE
  row_count int;
BEGIN
  #{ActiveRecord::Base.send(:sanitize_sql_array, args)};
  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE  '%', row_count;
END$$;
    SQL
      conn.execute(sql)
    else
      exec_sql(*args).cmd_tuples
    end
  end

  def exec_sql(*args)
    ActiveRecord::Base.exec_sql(*args)
  end


  # Executes the given block +retries+ times (or forever, if explicitly given nil),
  # catching and retrying SQL Deadlock errors.
  #
  # Thanks to: http://stackoverflow.com/a/7427186/165668
  #
  def self.retry_lock_error(retries=5, &block)
    begin
      yield
    rescue ActiveRecord::StatementInvalid => e
      if e.message =~ /deadlock detected/ and (retries.nil? || retries > 0)
        retry_lock_error(retries ? retries - 1 : nil, &block)
      else
        raise e
      end
    end
  end

  # Support for psql. If we want to support multiple RDBMs in the future we can
  # split this.
  def exec_sql_row_count(*args)
    exec_sql(*args).cmd_tuples
  end

end
