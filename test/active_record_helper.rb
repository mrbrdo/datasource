ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")
ActiveRecord::Migration.verbose = false
load "schema.rb"

def clean_db
  ActiveRecord::Base.connection.execute("DELETE FROM comments")
  ActiveRecord::Base.connection.execute("DELETE FROM posts")
  ActiveRecord::Base.connection.execute("DELETE FROM blogs")
  ActiveRecord::Base.connection.execute("DELETE FROM sqlite_sequence")
end
