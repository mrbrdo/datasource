require 'test_helper'
require 'active_record_helper'

class DatasourceTest < ActiveSupport::TestCase
  class PostsDatasource < Datasource.From(Post)
    computed_attribute :author, posts: [ :author_first_name, :author_last_name ] do
      { "name" => "#{author_first_name} #{author_last_name}" }
    end

    query_attribute :author_name, :posts do
      "posts.author_first_name || ' ' || posts.author_last_name"
    end
  end

  class BlogsDatasource < Datasource.From(Blog)
    includes_many :posts, PostsDatasource, :blog_id
  end

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
