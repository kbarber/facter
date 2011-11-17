require 'yaml'
require 'fileutils'
require 'digest'

# These exceptions are used only by the caching mechanism
class Facter::Util::CacheException < Exception; end

# This class provides a fact cache mechanism.
# TODO: better docs
class Facter::Util::Cache
  # TODO: autoload plugins, and provide facility to choose cache mechanism
  require 'facter/util/cache/persistent_hash'

  # The path to the cache directory
  attr_accessor :cachedir

  # Create and initialize the cache object
  def initialize
    options = {
      :path => Facter::Util::Config.cache_dir
    }

    # TODO: Allow cache mechanism to be chosen
    @cache = Facter::Util::Cache::PersistentHash.new(options)
  end

  # Stores cache based on key.
  #
  # * key - this is a string that this cache item is keyed from
  # * value - the value of the cache. Can be a string, array or hash or 
  #           combinations hereof
  # * ttl - this is the TTL to store with the entry that will be used for expiry
  #         calculations later on. It must be an integer no greater then 2^31.
  #         A zero indicates to never cache, and a -1 indicates cache forever.
  # TODO: find a way of setting a default for written ttl
  def set(key, value, ttl = 0)
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

    Facter.debug("Facter::Util::Cache.set(#{key}, #{value.inspect}, #{ttl})")

    # Prepare data to write
    data = {
      "data" => value,
      "stored" => Time.now.to_i,
      "ttl" => ttl,
      "key" => key
    }

    # Write to the memory cache
    @cache[key] = data
  end

  # Returns the cached items for a particular file.
  #
  # * key - the key to retrieve from the cache.
  # * override_ttl - allows us to override the TTL specified when it was stored
  # * noentry - what to return if there is really no entry. Since nil is a valid
  #             value we can't use nil.
  # TODO: use an options hash instead of just ttl so we can extend this.
  def get(key, override_ttl = nil, noentry = :noentry)
    # The key should only be a string.
    unless validate_key(key) then
      raise TypeError.new("key only accepts a String when using the set " \
        "method. It must be smaller then 256 characters and not be empty.")
    end

    # The TTL should be an integer between -1 and 2**31
    unless validate_ttl(override_ttl) or override_ttl.nil? then
      raise TypeError.new("ttl must be an integer between -1 and 2**31.")
    end

    Facter.debug("Facter::Util::Cache.get(#{key}, #{override_ttl}, #{noentry})")

    # If ttl zero return noentry
    if override_ttl.zero? then
      return noentry
    end

    # Retreive the entry from the backend store
    entry_data = @cache[key]

    # Grab a copy of the entry and return no entry if its nil
    if entry_data.nil? then
      return noentry
    end

    # Check validatity of data
    # TODO: more checks are needed
    unless entry_data.has_key?("data") then
      # TODO: this is probably bad - so we should raise an exception. It is
      #       no entry ... but its not that simple.
      raise Facter::Util::CacheException.new("No data element in the entry in " \
        "cache.")
    end

    # Either use the override_ttl specified in the get, or use
    # the ttl that was stored with the entry.
    use_ttl = override_ttl
    use_ttl ||= entry_data["ttl"]

    # Return the data entry immediately if ttl is -1
    if use_ttl == -1 then
      return entry_data["data"]
    end
 
    # TODO: should we be worried about stored time that is later then now?
    now = Time.now.to_i # epoch time from UTC - timezone shouldn't matter
    if (now - entry_data["stored"]) <= use_ttl then
      return entry_data["data"]
    else
      # Entry has expired - so return noentry
      return noentry
    end
  end

  # Delete an entry from the cache.
  # TODO: use an options hash so we can extend this.
  def delete(key)
    # The key should only be a string.
    unless validate_key(key) then
      raise TypeError.new("Key only accepts a String when using the set " \
        "method. It must be smaller then 256 characters and not be empty.")
    end

    # Delete an entry from the memory cache
    @cache.delete(key)

    # TODO: Will also need to delete this from the file cache
  end

  # Flushes the cache completely.
  def flush
    @cache.clear

    # TODO: we'll need to flush the file cache as well
  end

  private

  # Validate that an entry key is a String object and is no longer then 255 
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
end
