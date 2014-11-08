require 'test_helper'
require 'active_record_helper'

class SerializerCompositeTest < ActiveSupport::TestCase
  class PostsDatasource < Datasource::Base
    attributes :id, :title, :blog_id

    query_attribute :author_name, :posts do
      "posts.author_first_name || ' ' || posts.author_last_name"
    end
  end

  class BlogsDatasource < Datasource::Base
    attributes :id, :title
    includes_many :posts, PostsDatasource, :blog_id
  end

  class BlogsAndPostsSerializer < Datasource::Serializer::Composite
    hash do
      key :blogs do
        datasource BlogsDatasource
        attributes :id, :title,
          posts: { select: [ :id ], scope: Post.all }
      end

      key :posts do
        datasource PostsDatasource
        attributes :id, :title, :author_name
      end
    end
  end

  # SELECT blogs.id, blogs.title FROM "blogs"
  # SELECT posts.id, posts.blog_id FROM "posts"  WHERE (posts.blog_id IN (1,2))
  # SELECT posts.id, posts.title, (posts.author_first_name || ' ' || posts.author_last_name) as author_name FROM "posts"
  def test_blogs_and_posts_serializer
    blog = Blog.create! title: "Blog 1"
    blog.posts.create! title: "Post 1", author_first_name: "John", author_last_name: "Doe"
    blog.posts.create! title: "Post 2", author_first_name: "Maria", author_last_name: "Doe"
    blog = Blog.create! title: "Blog 2"

    serializer = BlogsAndPostsSerializer.new(Blog.all, Post.all)

    expected_result = {
      "blogs"=>[
        {"id"=>1, "title"=>"Blog 1", "posts"=>[
          {"id"=>1}, {"id"=>2}
        ]},
        {"id"=>2, "title"=>"Blog 2", "posts"=>[]}
      ],
      "posts"=>[
        {"id"=>1, "title"=>"Post 1", "author_name"=>"John Doe"},
        {"id"=>2, "title"=>"Post 2", "author_name"=>"Maria Doe"}
      ]
    }
    assert_equal(expected_result, serializer.as_json)
  end

  def teardown
    clean_db
  end
end
