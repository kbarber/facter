require 'facter/util/cache_plugin'

# SimpleHash provides a simple plugin implementation that is memory based.
#
# SimpleHash is not thread safe, so for this reason you must use it with care
# and should be seen as more of an example implementation of a CachePlugin.
class Facter::Util::Cache::SimpleHash < Facter::Util::CachePlugin

  # Path to cache
  attr_accessor :options

  # Create a new SimpleHash
  def initialize(options)
    # Store the options
    @options = options

    # Memory based storage for cache. Starts empty.
    @data = {}
  end

  # Return data based on key
  def get(key)
    # Try to return the key value
    entry = @data[key].dup unless @data[key].nil?

    if entry then
      return entry[:data]
    else
      return nil
    end
  end

  # Store value in key
  def set(key, val)
    @data[key] = {
      :data => val,
    }
  end

  # Clear all entries
  def clear
    @data.clear
  end

  # Delete an entry from the hash
  def delete(key)
    @data.delete(key)
  end
end
