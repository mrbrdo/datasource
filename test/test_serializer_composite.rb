require 'test_helper'
require 'active_record_helper'
require 'pry'

class PostsDatasource < Datasource::Base
  attributes :id, :title, :blog_id
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
      attributes :id, :title
    end
  end
end

class SerializerCompositeTest < ActiveSupport::TestCase
  # SELECT blogs.id, blogs.title FROM "blogs"
  # SELECT posts.id, posts.blog_id FROM "posts"  WHERE (posts.blog_id IN (1,2))
  # SELECT posts.id, posts.title FROM "posts"
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
        {"id"=>1, "title"=>"Post 1"},
        {"id"=>2, "title"=>"Post 2"}
      ]
    }
    assert_equal(expected_result, serializer.as_json)
  end

  def teardown
    clean_db
  end
end
