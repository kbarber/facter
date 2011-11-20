require 'sync'
require 'facter/util/cache_plugin'

# PersistentHash provides Hash-like behaviour but in a concurrent and
# peristent way.
#
# This cache is a two-tier cache, layer 1 uses a synchronised hash as a cache
# while layer 2 is file based providing persistence and the ability to share
# the cache amongst a number of processes.
class Facter::Util::Cache::PersistentHash < Facter::Util::CachePlugin

  # Path to cache
  attr_accessor :options

  # Create a new PersistentHash
  def initialize(options)
    Facter.debug("[#{self.class}#new] initialize with options " \
      "[#{options.inspect}]")

    # Keep a single YAML parser for performance reasons
    @yaml_parser = YAML.parser

    # Store the options
    @options = options

    # Memory based storage for cache. Starts empty.
    @data = {}

    Dir.glob(File.join(options[:path], "cache_*.yaml")).each do |file|
      loaded_data = load_file(file)
      @data[loaded_data[:data]["key"]] = loaded_data
    end

    Facter.debug("[#{self.class}#new] loaded facts from file cache [" +
      @data.keys.join(", ") + "]")

  ensure
    extend Sync_m
  end

  # Retrieves the value object corresponding to the key object. Retrieval is
  # performed using a shared lock for thread safe access to the hash data
  # layer.
  def get(key)
    Facter.debug("[#{self.class}#get] getting key [#{key}]")

    # We are grabbing a copy here within a shared lock for atomicity
    memory_entry = sync(:SH) do
      @data[key].dup unless @data[key].nil?
    end

    # Get file modification time
    file_mtime = cache_file_mtime(key)

    # If there is a memory entry and the file hasn't changed - just return
    # the memory entry
    if memory_entry and file_mtime.eql?(memory_entry[:file_mtime])
      return memory_entry[:data]
    # Otherwise grab the file_entry, if it exists and if there is a memory
    # entry evaluate which one is newer.
    elsif file_entry = load_entry(key) and memory_entry
      if file_entry[:data]["stored"] > memory_entry[:data]["stored"]
        sync(:EX) do
          @data[key] = file_entry
        end
      elsif file_entry[:data]["stored"] < memory_entry[:data]["stored"]
        file_entry = memory_entry
        save_entry(key, file_entry)
      end

      return file_entry[:data]
    # If there is no file_entry, just fall back to using the memory cache
    elsif memory_entry
      return memory_entry[:data]
    else
      return nil
    end
  end

  # Associates the value given by value with the key given by key. Storage
  # is performed using an exclusive lock for thread safety.
  def set(key, value)
    Facter.debug("[#{self.class}#set] setting key [#{key}] with value " \
      "[#{value.inspect}]")

    mtime = save_entry(key, value)

    sync(:EX) do
      @data[key] = {
        :file_mtime => mtime,
        :data => value,
      }
    end
  end

  # Clear all entries within the hash. Performed using an exclusive lock for
  # thread safety.
  def clear
    sync(:EX) do
      @data.clear
    end

    # TODO: should we clear disk?
  end

  # Delete an entry from the hash. Performed using an exclusive lock for
  # thread safety.
  def delete(key)
    Facter.debug("[#{self.class}#delete] deleting key [#{key}]")

    sync(:EX) do
      @data.delete(key)
    end
  end

  # A wrapper for performing locking operations.
  def sync(*args, &block)
    sync_synchronize(*args, &block)
  end

  # Load the cache from its backend storage.
  def load_entry(entry)
    load_file(cache_file(entry))
  end

  # Load a cache file returning a hash with :data and :file_mtime
  def load_file(filename)
    Facter.debug("[#{self.class}#load_file] loading file [#{filename}]")

    begin
      loaded_data = {}
      File.open(filename) do |f|
        loaded_data[:data] = @yaml_parser.load(f)
      end

      if loaded_data[:data].class != Hash then
        Facter.warnonce("Cache data is not valid from file #{filename}. " \
          "This could indicate a corruption, try deleting the file and " \
          "trying again. For now ignoring cache.")
        Facter.debug("[#{self.class}#load_file] Cache data is not valid " \
          "from file [#{filename}]. Data returned is " \
          "[#{loaded_data[:data].inspect}]")
        return nil
      end

      loaded_data[:file_mtime] = File.stat(filename).mtime.to_i

      Facter.debug("[#{self.class}#load_file] loaded from file " \
        "[#{filename}] data [#{loaded_data.inspect}]")

      return loaded_data
    rescue Errno::EACCES => e
      # Return a warning if the cache file is not readable
      Facter.warnonce("Cannot read cache data from cache area " \
        "#{options[:path]}. Check the path and its permissions and run " \
        "Facter in debug mode for more information")
      Facter.debug("[#{self.class}#load_file] cannot read cache data from " \
        "file [#{filename}] error is [#{e.message}]")
    rescue ArgumentError => e
      # Return a warning when the file is partially parseable but fails.
      Facter.warnonce("Cache data is not valid from file #{filename}. " \
        "This could indicate a corruption, try deleting the file and " \
        "trying again. For now ignoring cache.")
      Facter.debug("[#{self.class}#load_file] Cache data is not valid from " \
        "file [#{filename}] error is [#{e.message}]")
    rescue Errno::ENOENT
      # Do nothing if the file does not exist. This is non-fatal.
      Facter.debug("[#{self.class}#load_file] File does not exist " \
        "[#{filename}]")
    end

    return nil
  end

  # Writes cache to its backend storage.
  def save_entry(entry, data)
    Facter.debug("[#{self.class}#save_entry] writing entry [#{entry}] with " \
      "data [#{data.inspect}]")

    # Get the absolute path to a cache file based on the entry
    cache_file = cache_file(entry)

    # Save file
    save_file(cache_file, data)
  end

  # Writes cache to file
  def save_file(cache_file, data)
    Facter.debug("[#{self.class}#save_file] saving file [#{cache_file}] " \
      "with data [#{data.inspect}]")

    # Create a sufficently random temporary file
    tmp_cache_file = random_file(cache_file)

    # Mtime for cache checks later
    mtime = 0

    # Try to write to the temp file
    begin
      File.open(tmp_cache_file, "w", 0600) do |f|
        yaml = data.to_yaml
        f.write(yaml)
      end
      mtime = File.stat(tmp_cache_file).mtime.to_i
    rescue Errno::EACCES, Errno::ENOENT => e
      # Return a warning and debug message if the cache is not writeable but do
      # not fail as this should be a non-fatal error.
      Facter.warnonce("Cannot write to cache path #{options[:path]} check " \
        "permissions and run Facter in debug mode for more information")
      Facter.debug("[#{self.class}#save_file] cannot write temporary cache " \
        "file [#{options[:path]}] error is [#{e.message}]")

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
      Facter.warnonce("Cannot write to cache path #{options[:path]} check " \
        "permissions and run Facter in debug mode for more information")
      Facter.debug("[#{self.class}#save_file] cannot write cache " \
        "file [#{options[:path]}] error is [#{e.message}]")

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
    # This random file creation is loosely based on make_tmpname in the
    # 'tmpdir' module
    t = Time.now.strftime("%Y%m%d%H%M%S")
    "#{filename}-#{t}-#{$$}-#{rand(36**10).to_s(36)}"
  end

  # Cache file hash
  def hash_file(entry)
    Digest::SHA1.hexdigest(entry)
  end

  # Return an absolute path to a cache file based on entry
  def cache_file(entry)
    File.join(options[:path], "cache_" + hash_file(entry) + ".yaml")
  end

  # Returns the mtime of the specified cache file. Returns nil if there is
  # an error.
  def cache_file_mtime(entry)
    begin
      File.stat(cache_file(entry)).mtime.to_i
    rescue Errno::EACCES
      return nil
    rescue Errno::ENOENT
      return nil
    end
  end
end
