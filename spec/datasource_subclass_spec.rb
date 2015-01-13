require 'spec_helper'

module DatasourceSubclassSpec
  describe "Datasource::Base subclass" do
    class Post < ActiveRecord::Base
      belongs_to :blog
    end

    class PostDatasource < Datasource::From(Post)
      query :author_name do
        "posts.author_first_name || ' ' || posts.author_last_name"
      end
    end

    class PostSerializer < ActiveModel::Serializer
      attributes :id, :title, :author_name
    end

    it "works with #each" do
      post = Post.create! title: "The Post", author_first_name: "John", author_last_name: "Doe", blog_id: 10

      Post.for_serializer.each do |post|
        expect("The Post").to eq(post.title)
        expect("John Doe").to eq(post.author_name)
      end
    end
  end
end
