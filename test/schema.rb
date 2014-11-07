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

class Blog < ActiveRecord::Base
  self.table_name = "blogs"
  has_many :posts
end

class Post < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :blog
  has_many :comments
end

class Comment < ActiveRecord::Base
  self.table_name = "comments"
  belongs_to :post
end
