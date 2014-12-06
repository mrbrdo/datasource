require 'test_helper'
require 'active_record_helper'

class SerializerTest < ActiveSupport::TestCase
  class Post < ActiveRecord::Base
    belongs_to :blog

    datasource_module do
      query :author_name do
        "posts.author_first_name || ' ' || posts.author_last_name"
      end
    end
  end

  class Blog < ActiveRecord::Base
    has_many :posts
  end

  class BlogSerializer < ActiveModel::Serializer
    attributes :id, :title

    has_many :posts
  end

  class PostSerializer < ActiveModel::Serializer
    attributes :id, :title, :author_name
  end

  def test_blogs_and_posts_serializer
    blog = Blog.create! title: "Blog 1"
    blog.posts.create! title: "Post 1", author_first_name: "John", author_last_name: "Doe"
    blog.posts.create! title: "Post 2", author_first_name: "Maria", author_last_name: "Doe"
    blog = Blog.create! title: "Blog 2"

    expected_result = [
      {:id =>1, :title =>"Blog 1", :posts =>[
        {:id =>1, :title =>"Post 1", :author_name =>"John Doe"},
        {:id =>2, :title =>"Post 2", :author_name =>"Maria Doe"}
      ]},
      {:id =>2, :title =>"Blog 2", :posts =>[]}
    ]

    assert_query_count(2) do
      serializer = Datasource::ArrayAMS.new(Blog.all)
      assert_equal(expected_result, serializer.as_json)
    end
  end

  def teardown
    clean_db
  end
end
