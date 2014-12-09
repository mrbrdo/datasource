require 'test_helper'
require 'active_record_helper'

class ActiveRecordAdapterTest < ActiveSupport::TestCase
  class TestComment < ActiveRecord::Base
    self.table_name = "comments"
  end

  class TestPost < ActiveRecord::Base
    self.table_name = "posts"
    has_many :comments, class_name: "TestComment", foreign_key: "post_id"
    belongs_to :blog, class_name: "TestBlog", foreign_key: "blog_id", inverse_of: :posts

    datasource_module do
      computed :name_initials, :author_first_name, :author_last_name
      query :author_full_name, :posts,
        "posts.author_first_name || ' ' || posts.author_last_name"
    end

    def name_initials
      return unless author_first_name && author_last_name
      author_first_name[0].upcase + author_last_name[0].upcase
    end
  end

  class TestBlog < ActiveRecord::Base
    self.table_name = "blogs"
    has_many :posts, class_name: "TestPost", foreign_key: "blog_id", inverse_of: :blog
  end

  class TestCommentSerializer < ActiveModel::Serializer
    attributes :id
    # TODO:
    attributes :post_id
  end

  class TestMiniBlogSerializer < ActiveModel::Serializer
    attributes :id, :title
  end

  class TestPostSerializer < ActiveModel::Serializer
    attributes :id, :author_first_name, :author_full_name, :name_initials
    # TODO:
    attributes :blog_id
    has_many :comments
    has_one :blog, serializer: TestMiniBlogSerializer
  end

  class TestBlogSerializer < ActiveModel::Serializer
    attributes :id, :title
    has_many :posts
  end

  #def test_basic
  #  Blog.create! title: "Blog 1"
  #  assert_equal [{"id"=>1, "title"=>"Blog 1"}],
  #    MyBlogsDatasource.new(Blog.all).select(:id, :title).results
  #end

  def test_serializer
    blog = TestBlog.create! title: "Blog 1"
    post = blog.posts.create! author_first_name: "First", author_last_name: "Last"
    2.times { post.comments.create! comment: "Comment" }
    assert_query_count(3) do
      assert_equal Datasource::ArrayAMS.new(TestBlog.all).as_json,
        [{:id=>1, :title=>"Blog 1", :posts=>[{:id=>1, :author_first_name=>"First", :author_full_name=>"First Last", :name_initials=>"FL", :blog_id=>1, :comments=>[{:id=>1, :post_id=>1}, {:id=>2, :post_id=>1}], :blog=>{:id=>1, :title=>"Blog 1"}}]}]
    end
  end

  def test_scope
    blog = TestBlog.create! title: "Blog 1"
    post = blog.posts.create! author_first_name: "First", author_last_name: "Last"
    2.times { post.comments.create! comment: "Comment" }
    assert_query_count(3) do
      assert_equal TestBlogSerializer.new(TestBlog.for_serializer.first).as_json,
        {"test_blog"=>{ :id=>1, :title=>"Blog 1", :posts=>[{:id=>1, :author_first_name=>"First", :author_full_name=>"First Last", :name_initials=>"FL", :blog_id=>1, :comments=>[{:id=>1, :post_id=>1}, {:id=>2, :post_id=>1}], :blog=>{:id=>1, :title=>"Blog 1"}}]}}
    end
  end

  def teardown
    clean_db
  end
end
