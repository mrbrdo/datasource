db_path = File.expand_path("../../db.sqlite3")
ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => db_path)
Sequel::Model.db = Sequel.sqlite(db_path)
Sequel::Model.plugin :active_model
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define(:version => 0) do
  create_table :blogs, :force => true do |t|
    t.string :title
  end

  create_table :posts, :force => true do |t|
    t.integer :blog_id
    t.string :title
    t.string :author_first_name
    t.string :author_last_name
  end

  create_table :comments, :force => true do |t|
    t.integer :post_id
    t.text :comment
  end
end

ActiveRecord::Base.send :include, Datasource::Adapters::ActiveRecord::Model
Sequel::Model.send :include, ActiveModel::SerializerSupport

def expect_query_count(count)
  old_logger = ActiveRecord::Base.logger
  logger = StringIO.new
  ActiveRecord::Base.logger = Logger.new(logger)
  begin
    yield
  ensure
    ActiveRecord::Base.logger = old_logger
    # puts logger.string
  end
  expect(count).to eq(logger.string.lines.count)
end

def expect_query_count_sequel(count)
  logger_io = StringIO.new
  logger = Logger.new(logger_io)
  Sequel::Model.db.loggers << logger
  begin
    yield
  ensure
    Sequel::Model.db.loggers.delete(logger)
    # puts logger_io.string
  end
  expect(count).to eq(logger_io.string.lines.count)
end
