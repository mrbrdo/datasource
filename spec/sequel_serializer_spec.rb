require 'spec_helper'

module SequelSerializerSpec
  describe "Serializer (Sequel)", :sequel do
    class Post < Sequel::Model
      many_to_one :blog

      datasource_module do
        query :author_name do
          "posts.author_first_name || ' ' || posts.author_last_name"
        end
      end
    end

    class Blog < Sequel::Model
      one_to_many :posts
    end

    class PostSerializer < ActiveModel::Serializer
      attributes :id, :title, :author_name

      def author_name
        object.values[:author_name]
      end
    end

    class BlogSerializer < ActiveModel::Serializer
      attributes :id, :title

      has_many :posts, each_serializer: PostSerializer
    end

    it "returns serialized hash" do
      blog = Blog.create title: "Blog 1"
      Post.create blog_id: blog.id, title: "Post 1", author_first_name: "John", author_last_name: "Doe"
      Post.create blog_id: blog.id, title: "Post 2", author_first_name: "Maria", author_last_name: "Doe"
      blog = Blog.create title: "Blog 2"

      expected_result = [
        {:id =>1, :title =>"Blog 1", :posts =>[
          {:id =>1, :title =>"Post 1", :author_name =>"John Doe"},
          {:id =>2, :title =>"Post 2", :author_name =>"Maria Doe"}
        ]},
        {:id =>2, :title =>"Blog 2", :posts =>[]}
      ]

      expect_query_count_sequel(2) do
        serializer = ActiveModel::ArraySerializer.new(Blog.where, each_serializer: BlogSerializer)
        expect(expected_result).to eq(serializer.as_json)
      end
    end
  end
end
