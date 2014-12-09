require 'test_helper'
require 'active_record_helper'

class ScopeTest < ActiveSupport::TestCase
  class Post < ActiveRecord::Base
    belongs_to :blog

    datasource_module do
      query :author_name do
        "posts.author_first_name || ' ' || posts.author_last_name"
      end
    end
  end

  class PostSerializer < ActiveModel::Serializer
    attributes :id, :title, :author_name
  end

  def test_first
    Post.create! title: "The Post", author_first_name: "John", author_last_name: "Doe", blog_id: 10
    post = Post.for_serializer.first

    assert_equal("The Post", post.title)
    assert_equal("John Doe", post.author_name)
    assert_raises(ActiveModel::MissingAttributeError) { post.blog_id }
  end

  def test_find
    post = Post.create! title: "The Post", author_first_name: "John", author_last_name: "Doe", blog_id: 10
    post = Post.for_serializer.find(post.id)

    assert_equal("The Post", post.title)
    assert_equal("John Doe", post.author_name)
    assert_raises(ActiveModel::MissingAttributeError) { post.blog_id }
  end

  def test_each
    post = Post.create! title: "The Post", author_first_name: "John", author_last_name: "Doe", blog_id: 10

    Post.for_serializer.each do |post|
      assert_equal("The Post", post.title)
      assert_equal("John Doe", post.author_name)
      assert_raises(ActiveModel::MissingAttributeError) { post.blog_id }
    end
  end

  def teardown
    clean_db
  end
end
