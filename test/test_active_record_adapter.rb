require 'test_helper'
require 'active_record_helper'

class ActiveRecordAdapterTest < ActiveSupport::TestCase
  class MyBlogsDatasource < Datasource.From(Blog)
  end

  def test_basic
    Blog.create! title: "Blog 1"
    assert_equal [{"id"=>1, "title"=>"Blog 1"}],
      MyBlogsDatasource.new(Blog.all).select(:id, :title).results
  end

  def teardown
    clean_db
  end
end
