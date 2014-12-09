# Datasource

Automatically preload your ORM records for your serializer.

## Install

Add to Gemfile

```
gem 'datasource'
```

And `bundle install`.

Run install generator:

```
rails g datasource:install
```

### ORM support

- ActiveRecord
- Sequel

### Serializer support

- active_model_serializers

## Basic Usage

### Attributes
You don't have to do anything special.

```ruby
class UserSerializer < ActiveModel::Serializer
  attributes :id, :email
end
```

But you get an optimized query for free:

```sql
SELECT id, email FROM users
```

### Associations
You don't have to do anything special.

```ruby
class PostSerializer < ActiveModel::Serializer
  attributes :id, :title
end

class UserSerializer < ActiveModel::Serializer
  attributes :id
  has_many :posts
end
```

But you get automatic association preloading ("includes") with optimized queries for free:

```sql
SELECT id FROM users
SELECT id, title, user_id FROM posts WHERE id IN (?)
```

### Model Methods / Virtual Attributes
You need to specify which database columns a method depends on to be able to use it.
The method itself can be either in the serializer or in your model, it doesn't matter.

You can list multiple dependency columns.

```ruby
class User < ActiveRecord::Base
  datasource_module do
    computed :first_name_initial, :first_name
    computed :last_name_initial, :last_name
  end

  def first_name_initial
    first_name[0].upcase
  end
end

class UserSerializer < ActiveModel::Serializer
  attributes :first_name_initial, :last_name_initial

  def last_name_initial
    object.last_name[0].upcase
  end
end
```

```sql
SELECT first_name, last_name FROM users
```

You will be reminded with an exception if you forget to do this.

### Show action

You will probably want to reuse the same preloading rules in your show action.
You just need to call `.for_serializer` on the scope. You can optionally give it
the serializer class as an argument.

```ruby
class UsersController < ApplicationController
  def show
    post = Post.for_serializer.find(params[:id])
    # also works:
    # post = Post.for_serializer(PostSerializer).find(params[:id])

    render json: post
  end
end
```

## Advanced Usage

### Query attributes

You can specify a SQL fragment for `SELECT` and use that as an attribute on your
model. As a simple example you can concatenate 2 strings together in SQL:

```ruby
class User < ActiveRecord::Base
  datasource_module do
    query :full_name do
      "users.first_name || ' ' || users.last_name"
    end
  end
end

class UserSerializer < ActiveModel::Serializer
  attributes :id, :full_name
end
```

```sql
SELECT users.id, (users.first_name || ' ' || users.last_name) AS full_name FROM users
```

### Loaders

You might want to have some more complex preloading logic. In that case you can use a loader.
The loader will receive ids of the records, and you need to return a hash with your data.
The key of the hash must be the id of the record for which the data is.

A loader will only be executed if a computed attribute depends on it. If an attribute depends
on multiple loaders, pass an array of loaders like so `computed :attr, loaders: [:loader1, :loader2]`.

Be careful that if your hash does not contain a value for the object ID, the loaded value
will be nil.

```ruby
class User < ActiveRecord::Base
  datasource_module do
    computed :post_count, loaders: :post_counts
    loader :post_counts, array_to_hash: true do |user_ids|
      results = Post
        .where(user_id: user_ids)
        .group(:user_id)
        .pluck("user_id, COUNT(id)")
    end
  end
end

class UserSerializer < ActiveModel::Serializer
  attributes :id, :post_count

  def post_count
    # Will automatically give you the value for this user's ID
    object.loaded_values[:post_counts] || 0
  end
end
```

```sql
SELECT users.id FROM users
SELECT user_id, COUNT(id) FROM posts WHERE user_id IN (?)
```

Datasource provides shortcuts to transform your data into a hash. Here are examples:

```ruby
loader :stuff, array_to_hash: true do |ids|
  [[1, "first"], [2, "second"]]
  # will be transformed into
  # { 1 => "first", 2 => "second" }
end

loader :stuff, group_by: :user_id do |ids|
  Post.where(user_id: ids)
  # will be transformed into
  # { 1 => [#<Post>, #<Post>, ...], 2 => [ ... ], ... }
end

loader :stuff, group_by: :user_id, one: true do |ids|
  Post.where(user_id: ids)
  # will be transformed into
  # { 1 => #<Post>, 2 => #<Post>, ... }
end

loader :stuff, group_by: "user_id", one: true do |ids|
  # it works the same way on an array of hashes
  # but be careful about Symbol/String difference
  [{ "title" => "Something", "user_id" => 10 }]
  # will be transformed into
  # { 10 => { "title" => "Something", "user_id" => 10 } }
end
```
