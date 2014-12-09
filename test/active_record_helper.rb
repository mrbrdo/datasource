ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")
ActiveRecord::Migration.verbose = false
load "schema.rb"

def clean_db
  ActiveRecord::Base.connection.execute("DELETE FROM comments")
  ActiveRecord::Base.connection.execute("DELETE FROM posts")
  ActiveRecord::Base.connection.execute("DELETE FROM blogs")
  ActiveRecord::Base.connection.execute("DELETE FROM sqlite_sequence")
end

def assert_query_count(count)
  old_logger = ActiveRecord::Base.logger
  logger = StringIO.new
  ActiveRecord::Base.logger = Logger.new(logger)
  begin
    yield
  ensure
    ActiveRecord::Base.logger = old_logger
    puts logger.string
  end
  assert_equal count, logger.string.lines.count
end
