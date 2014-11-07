require 'test_helper'
require 'active_record_helper'
require 'pry'

class PostsDatasource < Datasource
  attributes :id, :title, :blog_id

  class Author < Datasource::ComputedAttribute
    depends posts: [ :author_first_name, :author_last_name ]

    def value
      {
        "name" => "#{author_first_name} #{author_last_name}"
      }
    end
  end
  attribute :author, Author

  class AuthorName < Datasource::QueryAttribute
    depends :posts

    def select_value
      "posts.author_first_name || ' ' || posts.author_last_name"
    end
  end
  attribute :author_name, AuthorName
end

class BlogsDatasource < Datasource
  attributes :id

  includes_many :posts, PostsDatasource, :blog_id
end

class DatasourceTest < ActiveSupport::TestCase
  def test_basic
    blog = Blog.create! title: "Blog 1"
    blog.posts.create! title: "Post 1", author_first_name: "John", author_last_name: "Doe"

    ds = PostsDatasource.new(Post.all)

    assert_equal [{"id"=>1, "title"=>"Post 1", "author_name"=>"John Doe", "author"=>{"name"=>"John Doe"}}],
      ds.select(:id, :title, :author, :author_name).results
  end

  def test_assoc
    blog = Blog.create! title: "Blog 1"
    blog.posts.create! title: "Post 1", author_first_name: "John", author_last_name: "Doe"

    ds = BlogsDatasource.new(Blog.all)

    assert_equal [{"id"=>1, "posts"=>[{"id"=>1, "author_name"=>"John Doe"}]}],
      ds.select(:id, posts: { scope: Post.all, select: [:id, :author_name] }).results
  end

  def teardown
    clean_db
  end
end
