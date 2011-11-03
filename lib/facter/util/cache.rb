require 'yaml'
require 'thread'
require 'facter/util/config'
require 'fileutils'

# These exceptions are used only by the caching mechanism
class Facter::Util::CacheException < Exception; end

# This exception allows us to signal no entry when querying the cache
# since nil is an acceptable return code.
# TODO: is this absolutely true?
class Facter::Util::CacheNoEntry < Facter::Util::CacheException; end

# This class provides a fact cache mechanism.
# TODO: better docs
class Facter::Util::Cache

  # The path to the cache file
  attr_accessor :cache_file
  # The mutex for cache writing
  attr_reader :cache_write_mutex

  # Create and initialize the cache object
  def initialize(path)
    # Check the path is a string first
    unless path.class == String then
      raise TypeError.new("Cache only accepts a string containing a file path " \
        "during initialization")
    end

    # This mutex is used for cache hash writing for thread safety.
    @cache_write_mutex = Mutex.new

    # Set the cache file.
    @cache_file = path

    # Load cache on initialization - must be done after we have a mutex
    # and a cache file.
    load
  end

  # Return a raw hash of all cached data.
  def to_hash
    @data
  end

  # Stores cache based on key.
  #
  # * key - this is a string that this cache item is keyed from
  # * value - the value of the cache. Can be a string, array or hash or 
  #           combinations hereof
  # * ttl - this is the TTL to store with the entry that will be used for expiry
  #         calculations later on. It must be an integer no greater then 2^31.
  #         A zero indicates to never cache, and a -1 indicates cache forever.
  # TODO: what should be the default here anyway?
  def set(key, value, ttl = -1)
    # The key should only be a string.
    unless validate_key(key) then
      raise TypeError.new("Key only accepts a String when using the set " \
        "method. It must be smaller then 256 characters and not be empty.")
    end

    # The value should only be a string, Hash or Array or combination thereof
    unless validate_value(value) then
      raise TypeError.new("Value only accepts Strings, Hashes, Arrays or " \
        "combinations thereof when using the set method. true, false and nil " \
        "is also acceptable on the right hand side of a Hash or in an Array.")
    end

    # The TTL should be an integer between -1 and 2**31
    unless validate_ttl(ttl) then
      raise TypeError.new("ttl must be an integer between -1 and 2**31.")
    end

    # Synchronize our changes to the @data hash
    @cache_write_mutex.synchronize {
      @data[key] = {:data => value, :stored => Time.now.to_i, :ttl => ttl}
    }

    # TODO: remove - this is just debugging
    #Facter.debug("XXX: Cache set on #{key} #{value} #{ttl} ... cache data is now #{Facter.cache.to_hash.inspect}")
  end

  # Returns the cached items for a particular file.
  #
  # * key - the key to retrieve from the cache
  # * override_ttl - allows us to override the TTL specified when it was stored
  # TODO: use an options hash instead of just ttl so we can extend this.
  # TODO: maybe we should return CacheItem objects instead of Exceptions. This
  #       way we indicate a failure with nil, but we can still get the value
  #       of nil with a 'value' method.
  # TODO: should we delete expired entries? This will break 'cache-only' options
  #       later on.
  def get(key, override_ttl = nil)
    # The key should only be a string.
    unless validate_key(key) then
      raise TypeError.new("Key only accepts a String when using the set " \
        "method. It must be smaller then 256 characters and not be empty.")
    end

    # The TTL should be an integer between -1 and 2**31
    unless validate_ttl(override_ttl) or override_ttl == nil then
      raise TypeError.new("ttl must be an integer between -1 and 2**31.")
    end

    # If ttl zero raise a no entry exception
    if override_ttl == 0 then
      raise Facter::Util::CacheNoEntry.new("ttl specified is zero so no " \
        "cache entry will ever be returned.")
    end

    # Check if there is even an entry
    unless @data.has_key?(key) then
      raise Facter::Util::CacheNoEntry.new("No entry in cache.")
    end
    if @data.has_key?(key) and !@data[key].has_key?(:data) then
      raise Facter::Util::CacheNoEntry.new("No data element in the entry in " \
        "cache.")
      # TODO: no data element means bad cache - probably need to deal with this
    end

    # Override the stored TTL if there is one specified in the get
    use_ttl = override_ttl
    use_ttl ||= @data[key][:ttl]

    # If TTL -1 - always return cache
    if use_ttl == -1 then
      return @data[key][:data]
    end
 
    # TODO: should we be worried about stored time that is later then now?
    now = Time.now.to_i # epoch time from UTC - timezone shouldn't matter
    if (now - @data[key][:stored]) <= use_ttl then
      return @data[key][:data]
    else
      raise Facter::Util::CacheNoEntry.new("Expired cache entry")
    end


  rescue Facter::Util::CacheException => e
    Facter.debug("no cache for #{key}: " + e.message)
    raise(e)
  end

  # Delete an entry from the cache.
  # TODO: use an options hash so we can extend this.
  def delete(key)
    # The key should only be a string.
    unless validate_key(key) then
      raise TypeError.new("Key only accepts a String when using the set " \
        "method. It must be smaller then 256 characters and not be empty.")
    end

    # Synchronize our changes to the @data hash
    @cache_write_mutex.synchronize {
      @data.delete(key)
    }
  end

  # Load the cache from its backend storage.
  def load
    # Load file or return an empty hash if there is a non-fatal problem
    loaded_data = {}
    begin
      # TODO: not sure how to deal with Windows locking here.
      loaded_data = YAML.load_file(@cache_file)

      # TODO: add better checks around the loaded file to make sure its valid
      if loaded_data.class != Hash then
        Facter.warnonce("Cache data is not valid. Using empty cache.")
        loaded_data = {}
      end
    rescue Errno::EACCES => e
      # Return a warning if the cache file is not readable
      Facter.warnonce("Cannot read from cache file: " + e.message)
    rescue ArgumentError => e
      # Return a warning when the file is partially parseable but fails.
      Facter.warnonce("Cache data is not valid. Using empty cache: " + e.message)
    rescue Errno::ENOENT
      # Do nothing if the file does not exist. This is non-fatal and the default
      # empty hash should be returned.
    end

    # Lock on mutex for storing the data to provide thread safety
    @cache_write_mutex.synchronize {
      @data = loaded_data
    }

    Facter.debug("XXX: loading data: #{@data.inspect}")
  end

  # Writes cache to its backend storage.
  def save
    # Create a sufficently random temporary file
    tmp_cache_file = random_file(@cache_file)

    # Get the data to write
    cache_data = @data

    Facter.debug("XXX: saving data: #{cache_data.inspect}")

    # Try to write to the temp file
    begin
      File.open(tmp_cache_file, "w", 0600) {|f| YAML.dump(cache_data, f) }
    rescue Errno::EACCES => e
      # Return a warning if the cache is not writeable but do not fail as this
      # should be a non-fatal error.
      Facter.warnonce("Cannot write to temporary cache file: " + e.message)

      # And bail from this function as we don't want to clobber
      # the real file.
      return
    end

    # Now move the temp cache file into its final place
    begin
      FileUtils.mv(tmp_cache_file, @cache_file)
    rescue Errno::EACCES => e
      # Return a warning if the cache is not writeable but do not fail as this
      # should be a non-fatal error.
      Facter.warnonce("Cannot write to cache file: " + e.message)

      # And bail from this function
      return
    ensure
      # Always try to cleanup tmp file if it still exists
      File.delete(tmp_cache_file) if File.exists?(tmp_cache_file)
    end
  end

  # Flushes the cache completely.
  def flush
    # Lock on mutex for storing the data to provide thread safety
    @cache_write_mutex.synchronize {
      @data = {}
    }
  end

  # Expire cache entries that are ready for expiration.
  # TODO: should we even use this? its a hard one - especially if we are
  #       going to have a 'cache_only' option in the future. Since facter
  #       offers no mechanism for seeing a canonical list of facts you
  #       can't even determine if a fact has disappeared easily.
  def expire
    # Iterate across each item look for expired items and remove them
    @data.each do |k, v|
    end
  end

  private

  # Validate that a key is a String object and is no longer then 255 
  # characters
  def validate_key(value)
    unless value.class == String then
      return false
    end

    if value.length < 1 or value.length > 255 then
      return false
    end

    return true
  end

  # Validate that an object is either a string, hash, array or
  # combination thereof.
  def validate_value(value)
    case value.class.to_s
    when "String","NilClass","TrueClass","FalseClass","Fixnum","Float" then
      return validate_value_rhs(value)
    when "Array" then
      return_value = true
      # Validate each item by calling validate again
      value.each do |item|
        unless validate_value(item) 
          return_value = false
          break
        end
      end
      return return_value
    when "Hash" then
      return_value = true
      value.each do |k,v|
        # Validate key first
        unless validate_value_lhs(k)
          return_value = false
          break
        end

        # Validate value by calling validate again
        unless validate_value(v)
          return_value = false
          break
        end
      end
      return return_value
    else
      return false
    end
  end

  # This method is used for validating the left hand side in
  # a hash.
  def validate_value_lhs(value)
    case value.class.to_s
    when "String"
      return true
    else
      return false
    end
  end

  # This method is used for validating the right hand side of
  # a hash or a single string element in an array or scalar.
  def validate_value_rhs(value)
    case value.class.to_s
    when "String","NilClass","TrueClass","FalseClass","Fixnum","Float"
      return true
    else
      return false
    end
  end

  # TTL validation
  def validate_ttl(value)
    if value.class != Fixnum
      return false
    end

    if value < -1 or value > 2**31 then
      return false
    end

    return true
  end

  # Return a random temp filename based on an original file
  def random_file(filename)
    filename + "." + Process.pid.to_s + "." +
      Time.now.to_i.to_s + "." + rand(999_999_999).to_s
  end

end
