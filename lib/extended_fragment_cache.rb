# In-Process Memory Cache for Fragment Caching
#
# Fragment caching has a slight inefficiency that requires two lookups 
# within the fragment cache store to render a single cached fragment.  
# The two cache lookups are:
#
# 1. The read_fragment method invoked in a controller to determine if a 
#    fragment has already been cached. e.g., 
#      unless read_fragment("/x/y/z")
#       ...
#      end
# 2. The cache helper method invoked in a view that renders the fragment. e.g., 
#      <% cache("/x/y/z") do %>
#        ...
#      <% end %>
#
# This plugin adds an in-process cache that saves the value retrieved from
# the fragment cache store.  The in-process cache has two benefits:
#
# 1. It cuts in half the number of read requests sent to the fragment cache
#    store.  This can result in a considerable saving for sites that make
#    heavy use of memcached.
# 2. Retrieving the fragment from the in-process cache is faster than going
#    to fragment cache store.  On a typical dev box, the savings are
#    relatively small but would be noticeable in standard production 
#    environment using memcached (where the fragment cache could be remote)
#
# Peter Zaitsev has a great post comparing the latencies of different
# cache types on the MySQL Performance blog:
# http://www.mysqlperformanceblog.com/2006/08/09/cache-performance-comparison/
#
# The plugin automatically installs a after_filter on the 
# ApplicationController that flushes the in-process memory cache at the 
# start of every request.

module ActionController
  module Caching
    module ExtendedFragments
      # Add a local_fragment_cache object and accessor.
      def self.append_features(base) #:nodoc:
        super
        base.class_eval do
          @@local_fragment_cache = {}
          @@fragment_cache_data = nil
          cattr_accessor :local_fragment_cache, :fragment_cache_data
        end

        # add an after filter to flush the local cache after every request
        base.after_filter({}) do |c|
          @@local_fragment_cache.clear
        end
      end
    end

    module Fragments
      # Override read_fragment so that it checks the local_fragment_cache
      # object before going to the fragment_cache_store backend.
      # - also allow fragments to be read using a class method (from a model)
      def read_fragment(name, options = nil)
        name = url_for(name.merge({:only_path => true})) if name.class == Hash
        ActionController::Caching::Fragments.read_fragment(name, options)
      end

      def self.read_fragment(name, options=nil)
        return unless ApplicationController.perform_caching

        key = self.fragment_cache_key(name)
        content = ApplicationController.local_fragment_cache[key]
        ApplicationController.benchmark "Fragment read: #{key}" do
          if content.nil?
            content = ActionController::Base.cache_store.read(key, options)
            ApplicationController.local_fragment_cache[key] = content
          end
        end

        if content.is_a?(Hash)
          ApplicationController.fragment_cache_data = content[:data]
          content[:body]
        else
          ApplicationController.fragment_cache_data = nil
          content
        end
      rescue NameError => err
        # ignore bogus uninitialized constant ApplicationController errors
      end

      def write_fragment(name, content, options=nil)
        name = url_for(name.merge({:only_path => true})) if name.class == Hash
        ActionController::Caching::Fragments.write_fragment(name, content, options)
      rescue NameError => err
        # ignore bogus uninitialized constant ApplicationController errors
        # when running Rails outside of web container
      end

      def self.write_fragment(name, content, options = nil)
        return unless ApplicationController.perform_caching

        key = self.fragment_cache_key(name)

        if ApplicationController.fragment_cache_data
          content = {
            :data => ApplicationController.fragment_cache_data,
            :body => content
          }
        end

        ApplicationController.benchmark "Cached fragment: #{key}" do
          ApplicationController.local_fragment_cache[key] = content
          ActionController::Base.cache_store.write(key, content, options)
        end

        content.is_a?(Hash) ? content[:body] : content
      rescue NameError => err
        # ignore bogus uninitialized constant ApplicationController errors
      end

      # Utility method needed by class methods
      def self.fragment_cache_key(name)
        name.is_a?(Hash) ? name.to_s : name
      end

      # Add expire_fragments as class method so that we can expire cached
      # content from models, etc.
      def self.expire_fragment(name, options = nil)
        return unless ApplicationController.perform_caching

        key = self.fragment_cache_key(name)

        if key.is_a?(Regexp)
          ApplicationController.benchmark "Expired fragments matching: #{key.source}" do
            ActionController::Base.cache_store.delete_matched(key, options)
          end
        else
          ApplicationController.benchmark "Expired fragment: #{key}" do
            ActionController::Base.cache_store.delete(key, options)
          end
        end
      rescue NameError => err
        # ignore bogus uninitialized constant ApplicationController errors
      end
    end
  end
end

# Content Interpolation for Fragment Caching
#
# Many modern websites mix a lot of static and dynamic content.  The more
# dynamic content you have in your site, the harder it becomes to implement
# caching.  In an effort to scale, you've implemented fragment caching
# all over the place.  Fragment caching can be difficult if your static content
# is interleaved with your dynamic content.  Your views become littered
# with cache calls which not only hurts performance (multiple calls to the
# cache backend), it also makes them harder to read.  Content 
# interpolation allows you substitude dynamic content into cached fragment.
#
# Take this example view:
# <% cache("/first_part") do %>
#   This content is very expensive to generate, so let's fragment cache it.<br/>
# <% end %>
# <%= Time.now %><br/>
# <% cache("/second_part") do %>
#   This content is also very expensive to generate.<br/>
# <% end %>
#
# We can replace it with:
# <% cache("/only_part", {}, {"__TIME_GOES_HERE__" => Time.now}) do %>
#   This content is very expensive to generate, so let's fragment cache it.<br/>
#   __TIME_GOES_HERE__<br/>
#   This content is also very expensive to generate.<br/>
# <% end %>
#
# The latter is easier to read and induces less load on the cache backend.
#
# We use content interpolation at Zvents to speed up our JSON methods.
# Converting objects to JSON representation is notoriously slow.  
# Unfortunately, in our application, each JSON request must return some unique
# data.  This makes caching tedious because 99% of the content returned is
# static for a given object, but there's a little bit of dynamic data that
# must be sent back in the response.  Using content interpolation, we cache
# the object in JSON format and substitue the dynamic values in the view.
# 
# This plugin integrates Yan Pritzker's extension that allows content to be 
# cached with an expiry time (from the memcache_fragments plugin) since they 
# both operate on the same method.  This allows you to do things like:
#
# <% cache("/only_part", {:expire => 15.minutes}) do %>
#   This content is very expensive to generate, so let's fragment cache it.
# <% end %>

module ActionView
  module Helpers
    # See ActionController::Caching::Fragments for usage instructions.
    module CacheHelper
      def cache(key, options={}, interpolation={}, &block)
        if key.blank? or (options.has_key?(:if) and !options[:if])
          yield
        else
          begin
            content = @controller.fragment_for(output_buffer, key, options, interpolation, &block) || ""
          rescue MemCache::MemCacheError => err
            content = ""
          end

          interpolation.keys.each{|k| content.gsub!(k.to_s, interpolation[k].to_s)}
          content
        end
      end
    end
  end
end

module ActionController
  module Caching
    module Fragments
      # Called by CacheHelper#cache
      def fragment_for(buffer, name={}, options=nil, interpolation={}, &block)
        unless (perform_caching && cache_store) then
          content = block.call
          interpolation.keys.each{|k| content.gsub!(k.to_s,interpolation[k].to_s)}
          content
          return
        end

        if cache = read_fragment(name, options)
          buffer.concat(cache)
        else
          pos = buffer.length
          block.call
          write_fragment(name, buffer[pos..-1], options)
          interpolation.keys.each{|k|
            buffer[pos..-1] = buffer[pos..-1].gsub(k.to_s,interpolation[k].to_s) if buffer[pos..-1].include?(k.to_s)
          }
          buffer[pos..-1]
        end
      end
    end
  end
end

class MemCache
  # The read and write methods are required to get fragment caching to 
  # work with the Robot Co-op memcache_client code.
  # http://rubyforge.org/projects/rctools/
  #
  # Lifted shamelessly from Yan Pritzker's memcache_fragments plugin.
  # This should really go back into the memcache_client core.
  # http://skwpspace.com/2006/08/19/rails-fragment-cache-with-memcached-client-and-time-based-expire-option/
  def read(key, options=nil)
    options ||= {}
    common_key = options[:common_key]
    cache = options[:cache] || self
    if common_key
      cached_data = self.get_multi(key, common_key) || {}
      Zvents::CommonKeyCache._get_value(cache, key, common_key, cached_data)
    else
      cache.get(key, options[:raw] || false)
    end
  end

  def write(key,content,options=nil)
    options ||= {}
    cache = options[:cache] || self
    expiry = options && options[:expire] || 0
    common_key = options[:common_key]
    if common_key
      Zvents::CommonKeyCache._set(cache, key, common_key, content, expiry)
    else
      cache.set(key, content, expiry, options[:raw] || false)
    end
  end
end

# ActionController::Base.send :include, ActionController::Caching::ExtendedFragments
