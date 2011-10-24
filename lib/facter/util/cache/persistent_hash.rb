require 'sync'

# ConcurrentHash provides Hash-like behaviour but in a concurrent way.
#
# It uses shared locks for retrieval and exclusive locks for modification
# to ensure thread safety.
class Facter::Util::Cache::PersistentHash

  # Path to cache
  attr_accessor :cachedir

  # Create a new ConcurrentHash
  def initialize(options)
    # Keep a single YAML parser for performance reasons
    @yaml_parser = YAML.parser

    # Set the cachedir
    @cachedir = options[:path]

    # Memory based storage for cache. Starts empty.
    @data = {}

    Dir.glob(File.join(cachedir, "cache_*.yaml")).each do |file|
      mtime = File.stat(file).mtime.to_i
      loaded_data = load_file(file)
      loaded_data["file_mtime"] = mtime
      @data[loaded_data["key"]] = loaded_data
    end

  ensure
    extend Sync_m
  end

  # Retrieves the value object corresponding to the key object. Retrieval is
  # performed using a shared lock for thread safe access to the hash data layer.
  def [](key)
    Facter.debug("Facter::Util::Cache::PersistentHash.[](#{key})")

    sync(:SH) do

      # Get file modification time
      file_mtime = nil
      begin
        file_mtime = File.stat(cache_file(key)).mtime.to_i
      rescue Errno::ENOENT
      end

      # Get memory entry
      memory_entry = @data[key]

      # If there is a memory entry and the file hasn't changed - just return
      # the memory entry
      if memory_entry and file_mtime.eql?(memory_entry["file_mtime"])
        return memory_entry
      elsif file_entry = load_entry(key)
        if file_entry["stored"] > memory_entry["stored"]
          @data[key] = file_entry
        elsif file_entry["stored"] < memory_entry["stored"]
          file_entry = memory_entry
          save_entry(key, file_entry)
        end

        return file_entry
      else
        return nil
      end

    end
  end

  # Associates the value given by value with the key given by key. Storage
  # is performed using an exclusive lock for thread safety.
  def []=(key, val)
    Facter.debug("Facter::Util::Cache::PersistentHash.[]=(#{key},#{val.inspect})")

    sync(:EX) do
      val.delete("file_mtime")
      mtime = save_entry(key, val)
      val["file_mtime"] = mtime

      @data[key] = val
    end
  end

  # Clear all entries within the hash. Performed using an exclusive lock for
  # thread safety.
  def clear
    sync(:EX) do
      @data.clear
    end
  end

  # Delete an entry from the hash. Performed using an exclusive lock for
  # thread safety.
  def delete(key)
    sync(:EX) do
      @data.delete(key)
    end
  end

  private

  # A wrapper for performing locking operations.
  def sync(*args, &block)
    sync_synchronize(*args, &block)
  end

  # Load the cache from its backend storage.
  def load_entry(entry)
    Facter.debug("Facter::Util::Cache::PersistentHash.load_entry(#{entry})")

    load_file(cache_file(entry))
  end

  # Load a cache file.
  def load_file(filename)
    loaded_data = nil
    begin
      # TODO: not sure how to deal with Windows locking here.
      # TODO: stat the file first to decide if we should even load it
      #       the parse operating is terribly slow.
      File.open(filename) do |f|
        loaded_data = @yaml_parser.load(f)
      end
      
      # TODO: add better checks around the loaded file to make sure its valid
      if loaded_data.class != Hash then
        Facter.warnonce("Cache data is not valid for file [#{filename}]. Using empty cache.")
        # TODO: should this be a noentry? Or an exception?
        return nil
      end

      loaded_data["file_mtime"] = File.stat(filename).mtime.to_i
    rescue Errno::EACCES => e
      # Return a warning if the cache file is not readable
      Facter.warnonce("Cannot read cache data for file [#{filename}]: " + e.message)
    rescue ArgumentError => e
      # Return a warning when the file is partially parseable but fails.
      Facter.warnonce("Cache data is not valid for file [#{filename}]. Using empty cache: " + e.message)
    rescue Errno::ENOENT
      # Do nothing if the file does not exist. This is non-fatal.
    end

    return loaded_data
  end

  # Writes cache to its backend storage.
  def save_entry(entry, data)
    Facter.debug("Facter::Util::Cache::PersistentHash.save_entry(#{entry},#{data.inspect})")

    # Get the absolute path to a cache file based on the entry
    cache_file = cache_file(entry)

    # Create a sufficently random temporary file
    tmp_cache_file = random_file(cache_file)

    # Mtime for cache checks later
    mtime = 0

    # Try to write to the temp file
    begin
      File.open(tmp_cache_file, "w", 0600) do |f|
        data.to_yaml(f)
      end
      mtime = File.stat(tmp_cache_file).mtime.to_i
    rescue Errno::EACCES => e
      # Return a warning if the cache is not writeable but do not fail as this
      # should be a non-fatal error.
      Facter.warnonce("Cannot write to temporary cache file for entry [#{entry}]: " + e.message)

      # And bail from this function as we don't want to clobber
      # the real file.
      return
    end

    # Now move the temp cache file into its final place
    begin
      FileUtils.mv(tmp_cache_file, cache_file)
    rescue Errno::EACCES => e
      # Return a warning if the cache is not writeable but do not fail as this
      # should be a non-fatal error.
      Facter.warnonce("Cannot write to cache file for entry [#{entry}]: " + e.message)

      # And bail from this function
      return
    ensure
      # Always try to cleanup tmp file if it still exists
      File.delete(tmp_cache_file) if File.exists?(tmp_cache_file)
    end

    return mtime
  end

  # Return a random temp filename based on an original file
  def random_file(filename)
    filename + "." + Process.pid.to_s + "." +
      Time.now.to_i.to_s + "." + rand(999_999_999).to_s
  end

  # Cache file hash
  def hash_file(entry)
    Digest::SHA1.hexdigest(entry)
  end

  # Return an absolute path to a cache file based on entry
  def cache_file(entry)
    File.join(@cachedir, "cache_" + hash_file(entry) + ".yaml")
  end
end
