#!/usr/bin/env ruby

require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

require 'facter/util/cache'

describe Facter::Util::Cache do
  include FacterSpec::Files

  describe "during initialization" do
    it "should create a valid object" do
      cache_obj = Facter::Util::Cache.new(tmpfile)
      cache_obj.class.should == Facter::Util::Cache
    end

    it "should call load to load the cache" do
      Facter::Util::Cache.any_instance().expects(:load)
      cache_obj = Facter::Util::Cache.new(tmpfile)
    end

    describe "when cache file is not readable" do
      let(:cache_file) { tmpfile }
      let(:cache_obj) { Facter::Util::Cache.new(cache_file) }

      before :each do
        # Silence warnings
        Kernel.stubs(:warn)

        # Empty file
        File.open(cache_file, "w") { |f| f.write("") }

        # Make cache file read-only
        File.chmod(0000, cache_file)
      end

      after :each do
        # Reset permissions so files can be cleaned up
        File.chmod(0644, cache_file)
      end

      it "using the memory cache should still work" do
        cache_obj.to_hash.should == {}
      end

      it "should return warning" do
        Facter.expects(:warnonce).with(regexp_matches(/^Cannot read from cache file: /))
        cache_obj.to_hash == {}
      end
    end

    describe "when validating the path argument" do
      describe "should throw an error if it is not a valid String, " do
        invalid_items = [
          ["item1","item2"],
          {"key1" => "val1"},
          Object.new,
          Class,
          1,
          1.1,
          :symbol,
        ]
        invalid_items.each do |invalid_item|
          it "for example: #{invalid_item.inspect}" do
            expect { Facter::Util::Cache.new(invalid_item) }.should(
              raise_error(TypeError, "Cache only accepts a string " \
              "containing a file path during initialization")
            )
          end
        end
      end
    end

    # TODO: tests for bad load files
  end

  describe "when using method" do
    let(:cache_file) { tmpfile }
    let(:cache_obj) { Facter::Util::Cache.new(cache_file) }

    describe "to_hash" do
      it "should return an empty hash when no cache items exist" do
        cache_obj.to_hash.should == {}
      end

      it "should just return the internal @data object in its raw form" do
        cache_obj.set("key1", "value1", 1)
        cache_obj.to_hash.should == cache_obj.instance_variable_get("@data")
      end
    end

    describe "set" do
      it "should accept a valid key and value without error" do
        cache_obj.set("key1", "value1")
      end

      it "should accept a valid key, value and ttl without error" do
        cache_obj.set("key1", "value1", 1)
      end

      it "should cache forever when set to -1" do
        cache_obj.set("foo", "bar", -1)

        now = Time.now
        Time.stubs(:now).returns(now + 1_000_000)

        cache_obj.get("foo").should == "bar"
      end

      # Validation tests
      describe "when validating the key parameter" do
        describe "should not throw an error when it is valid, " do
          valid_items = [
            "key1",
            "operatingsystem",
            "ipaddress_eth0",
            "is_virtual",
          ]
          valid_items.each do |valid_item|
            it "for example: #{valid_item.inspect}" do
              expect { cache_obj.set(valid_item, "value") }.should_not(
                raise_error(TypeError)
              )
            end
          end
        end

        describe "should thrown an error when it is not valid, " do
          invalid_items = [
            ["item1","item2"],
            {"key1" => "value1"},
            Object.new,
            Class,
            "a" * 256,
            1,
            1.1,
            :symbol,
            "",
            nil,
          ]
          invalid_items.each do |invalid_item|
            it "for example: #{invalid_item.inspect}" do
              expect { cache_obj.set(invalid_item, "value") }.should(
                raise_error(TypeError, "Key only accepts a String " \
                "when using the set method. It must be smaller then 256 " \
                "characters and not be empty.")
              )
            end
          end
        end
      end

      describe "when validating the value parameter" do
        describe "should not throw an error when it is valid, " do
          valid_items = [
            nil,
            true,
            false,
            "key1",
            3,
            45.6766,
            -53,
            {"key1" => "value1"},
            ["item1", "item2"],
            {"key1" => ["item1","item2"]},
            {"key1" => nil},
            {"key1" => ""},
            ["item1", nil],
            ["item1", ""],
            [true, false],
            [true, "", "bar"],
            {"key1" => true},
          ]
          valid_items.each do |valid_item|
            it "for example: #{valid_item.inspect}" do
              expect { cache_obj.set("key", valid_item) }.should_not(
                raise_exception(TypeError)
              )
            end
          end
        end

        describe "should thrown an error when it is not valid, " do
          invalid_items = [
            Object.new,
            Class,
            :symbol,
            ["item1", Object.new],
            {"key1" => Object.new},
            {nil => "value1"},
            {"key1" => {"key2" => Object.new}},
            {"key1" => {"key2" => ["item1", Object.new] } },
            {"key1" => {"key2" => ["item1", :symbol] } },
          ]
          invalid_items.each do |invalid_item|
            it "for example: #{invalid_item.inspect}" do
              expect { cache_obj.set("key", invalid_item) }.should(
                raise_error(TypeError, "Value only accepts Strings, " \
                "Hashes, Arrays or combinations thereof when using the set " \
                "method. true, false and nil is also acceptable on the right " \
                "hand side of a Hash or in an Array.")
              )
            end
          end
        end
      end

      describe "when validating the ttl parameter" do
        describe "should not throw an error when it is valid, " do
          valid_items = [
            0,
            -1,
            15,
            3_200_300,
            2**31,
          ]
          valid_items.each do |valid_item|
            it "for example: #{valid_item.inspect}" do
              expect { cache_obj.set("key", "value", valid_item) }.should_not(
                raise_error(TypeError)
              )
            end
          end
        end

        describe "should thrown an error when it is not valid, " do
          invalid_items = [
            ["item1","item2"],
            {"key1" => "value1"},
            Object.new,
            Class,
            "a" * 256,
            -15,
            (2**31)+1,
            1.1,
            :symbol,
            "",
            nil,
          ]
          invalid_items.each do |invalid_item|
            it "for example: #{invalid_item.inspect}" do
              expect { cache_obj.set("key", "value", invalid_item) }.should(
                raise_error(TypeError, "ttl must be an integer between -1 " \
                "and 2**31.")
              )
            end
          end
        end

      end
    end

    describe "get" do
      before :each do
        # Set a value first for the following tests
        cache_obj.set("key1", "value1")
      end

      it "should accept a valid key without error" do
        cache_obj.get("key1")
      end

      it "should accept a valid key and ttl without error" do
        cache_obj.get("key1", 1)
      end

      it "should retrieve the correct value after using set" do
        cache_obj.get("key1").should == "value1"
      end

      it "should use stored ttl by default" do
        cache_obj.set("key1", "value1", 5)

        # Wind forward time
        now = Time.now
        Time.stubs(:now).returns(now + 7)

        # Now we should get a noentry
        expect { cache_obj.get("key1") }.should(
          raise_error(Facter::Util::CacheNoEntry, "Expired cache entry")
        )
      end

      it "should allow us to override the ttl" do
        cache_obj.set("key1", "value1", 5)

        # Wind forward time
        now = Time.now
        Time.stubs(:now).returns(now + 7)

        # Now we should get a valid return
        cache_obj.get("key1", 15).should == "value1"
      end

      it "should be able to return data previously saved to disk" do
        cache_obj.set("foo", "bar", 5)
        cache_obj.save
   
        cache_obj.load
        cache_obj.get("foo").should == "bar"
      end

      it "should throw a CacheNoEntry exception when ttl has expired" do
        cache_obj.set("foo", "bar", 5)
        cache_obj.get("foo").should == "bar"

        now = Time.now
        Time.stubs(:now).returns(now + 30)
        expect { cache_obj.get("foo",1) }.should(
          raise_error(Facter::Util::CacheNoEntry, "Expired cache entry")
        )
      end

      it "should cache forever when ttl set to -1" do
        cache_obj.set("foo", "bar", 1)

        now = Time.now
        Time.stubs(:now).returns(now + 1_000_000)

        cache_obj.get("foo", -1).should == "bar"
      end

      # Validation tests
      describe "when validating the key parameter" do
        describe "should not throw an error when it is valid, " do
          valid_items = [
            "key1",
            "operatingsystem",
            "virtual",
            "is_virtual",
            "ipaddress_eth0",
          ]
          valid_items.each do |valid_item|
            it "for example: #{valid_item.inspect}" do
              expect { cache_obj.get(valid_item) }.should_not(
                raise_error(TypeError)
              )
            end
          end
        end

        describe "should thrown an error when it is not valid, " do
          invalid_items = [
            ["item1","item2"],
            {"key1" => "value1"},
            Object.new,
            Class,
            "a" * 256,
            1,
            1.1,
            :symbol,
            "",
            nil,
          ]
          invalid_items.each do |invalid_item|
            it "for example: #{invalid_item.inspect}" do
              expect { cache_obj.get(invalid_item) }.should(
                raise_error(TypeError, "Key only accepts a String " \
                "when using the set method. It must be smaller then 256 " \
                "characters and not be empty.")
              )
            end
          end
        end
      end

      describe "when validating the override_ttl parameter" do
        describe "should not throw an error when it is valid, " do
          valid_items = [
            nil,
            0,
            -1,
            15,
            3_200_300,
            2**31,
          ]
          valid_items.each do |valid_item|
            it "for example: #{valid_item.inspect}" do
              expect { cache_obj.get("key1", valid_item) }.should_not(
                raise_error(TypeError)
              )
            end
          end
        end

        describe "should thrown an error when it is not valid, " do
          invalid_items = [
            ["item1","item2"],
            {"key1" => "value1"},
            Object.new,
            Class,
            "a" * 256,
            -15,
            (2**31)+1,
            1.1,
            :symbol,
            "",
          ]
          invalid_items.each do |invalid_item|
            it "for example: #{invalid_item.inspect}" do
              expect { cache_obj.get("key", invalid_item) }.should(
                raise_error(TypeError, "ttl must be an integer between -1 " \
                "and 2**31.")
              )
            end
          end
        end
      end
    end

    describe "delete" do
      it "should accept a valid key without error" do
        cache_obj.delete("key1")
      end

      it "should clear the object when used" do
        cache_obj.set("key1", "value1", -1)
        cache_obj.get("key1").should == "value1"
        cache_obj.delete("key1")
        expect { cache_obj.get("key1") }.should(
          raise_error(Facter::Util::CacheNoEntry, "No entry in cache.")
        )
      end

      # Validation tests
      describe "when validating the key parameter" do
        describe "should not throw an error when it is valid, " do
          valid_items = [
            "key1",
            "operatingsystem",
            "ipaddress_eth0",
            "is_virtual", 
            "virtual",
          ]
          valid_items.each do |valid_item|
            it "for example: #{valid_item.inspect}" do
              expect { cache_obj.delete(valid_item) }.should_not(
                raise_error(TypeError)
              )
            end
          end
        end

        describe "should thrown an error when it is not valid, " do
          invalid_items = [
            ["item1","item2"],
            {"key1" => "value1"},
            Object.new,
            Class,
            "a" * 256,
            1,
            1.1,
            :symbol,
            "",
            nil,
          ]
          invalid_items.each do |invalid_item|
            it "for example: #{invalid_item.inspect}" do
              expect { cache_obj.delete(invalid_item) }.should(
                raise_error(TypeError, "Key only accepts a String when " \
                "using the set method. It must be smaller then 256 " \
                "characters and not be empty.")
              )
            end
          end
        end
      end
    end

    describe "save" do
      it "should run without error" do
        cache_obj.save
      end

      it "should create the necessary file when ran" do
        cache_obj.save
        File.should be_exist(cache_file)
      end

      describe "when temp cache file is not writeable" do
        let(:tmp_cache_file) { tmpfile }

        before :each do
          # Silence warnings
          Kernel.stubs(:warn)

          cache_obj.expects(:random_file).returns(tmp_cache_file)
          File.open(tmp_cache_file, "w") do |f|
            f.write("")
          end
          File.chmod(0000, tmp_cache_file)
        end

        after :each do
          # Reset permissions so files can be cleaned up
          File.chmod(0644, tmp_cache_file)
        end

        it "setting and getting memory cache should still work" do
          cache_obj.set("foo", "bar", 5)
          cache_obj.save
          cache_obj.get("foo").should == "bar"
        end

        it "should return warning" do
          Facter.expects(:warnonce).with(regexp_matches(/^Cannot write to temporary cache file: /))
          cache_obj.set("foo", "bar", 5)
          cache_obj.save
        end
      end

      describe "when cache file is not writeable" do
        let(:cache_file_dir) { tmpdir }
        let(:cache_file) { cache_file_dir + "/cache" }
        let(:tmp_cache_file) { tmpfile }
        let(:cache_obj) { Facter::Util::Cache.new(cache_file) }

        before :each do
          # Silence warnings
          Kernel.stubs(:warn)

          # Modify dir permissions instead of file permissions
          # as a move operation will blat file permissions
          File.chmod(0000, cache_file_dir)

          # Stub tmp_cache_file so it returns the writeable version
          cache_obj.expects(:random_file).returns(tmp_cache_file)
        end

        after :each do
          # Reset permissions so files can be cleaned up
          File.chmod(0644, cache_file_dir)
        end

        it "setting and getting memory cache should still work" do
          cache_obj.set("foo", "bar", 5)
          cache_obj.save
          cache_obj.get("foo").should == "bar"
        end

        it "should return warning" do
          cache_obj.set("foo", "bar", 5)
          Facter.expects(:warnonce).with(regexp_matches(/^Cannot write to cache file: /))
          cache_obj.save
        end

        it "temporary cache file should be cleaned up after attempt" do
          cache_obj.set("foo", "bar", 5)
          cache_obj.save
          File.exists?(tmp_cache_file).should be_false
        end
      end
    end

    describe "load" do
      it "should run without error" do
        cache_obj.load
      end

      it "should allow loading, saving, flushing and loading and still preserve cache" do
        cache_obj.load
        cache_obj.to_hash.should == {}

        cache_obj.set("foo", "bar", 5)
        cache_obj.save

        cache_obj.flush

        cache_obj.load
        cache_obj.get("foo").should == "bar"
      end

      describe "when cache file has invalid data should warn and return empty data set" do
        it "for example - a string" do
          File.open(cache_file, "w") do |f|
            f.write("---\nfoobar data")
          end

          Facter.expects(:warnonce).twice.with("Cache data is not valid. Using empty cache.")
          cache_obj.load
          cache_obj.to_hash.should == {}
        end

        it "for example - an array" do
          File.open(cache_file, "w") do |f|
            f.write("---\n- foo\n- bar\n")
          end

          Facter.expects(:warnonce).twice.with("Cache data is not valid. Using empty cache.")
          cache_obj.load
          cache_obj.to_hash.should == {}
        end

        it "for example - json data" do
          File.open(cache_file, "w") do |f|
            f.write('{"key1":"value1"}')
          end

          Facter.expects(:warnonce).twice.with(regexp_matches(/^Cache data is not valid. Using empty cache/))
          cache_obj.load
          cache_obj.to_hash.should == {}
        end
      end

      it "should retain the data age when storing on disk" do
        cache_obj.set("foo", "bar", 1)
        cache_obj.save

        cache_obj.load

        now = Time.now
        Time.stubs(:now).returns(now + 30)

        expect { cache_obj.get("foo") }.should(
          raise_error(Facter::Util::CacheNoEntry, "Expired cache entry")
        )
      end

      it "should be able to return both old and new data when loading from disk" do
        cache_obj.set("foo", "bar", 5)
        cache_obj.save

        cache_obj.flush

        cache_obj.load
        cache_obj.get("foo").should == "bar"
        cache_obj.set("biz", "baz", 5)
        cache_obj.save

        cache_obj.flush

        cache_obj.load

        cache_obj.get("biz").should == "baz"
        cache_obj.get("foo").should == "bar"
        cache_obj.get("biz").should == "baz"
      end

      describe "when cache file becomes not readable" do
        let(:cache_file) { tmpfile }
        let(:cache_obj) { Facter::Util::Cache.new(cache_file) }

        before :each do
          # Silence warnings
          Kernel.stubs(:warn)

          # Empty file
          File.open(cache_file, "w") { |f| f.write("") }
        end

        after :each do
          # Reset permissions so files can be cleaned up
          File.chmod(0644, cache_file)
        end

        it "setting and getting memory cache should still work" do
          cache_obj.to_hash.should == {}

          # Make cache file read-only
          File.chmod(0000, cache_file)

          cache_obj.load
          cache_obj.to_hash.should == {}
        end

        it "should return warning" do
          cache_obj.to_hash.should == {}

          # Make cache file read-only
          File.chmod(0000, cache_file)

          Facter.expects(:warnonce).with(regexp_matches(/^Cannot read from cache file: /))
          cache_obj.load
        end
      end

      # TODO: use fixtures to load pre-arranged caches valid/invalid
    end

    describe "flush" do
      it "should run without error" do
        cache_obj.flush
      end

      it "should wipe out internal hash when it has data" do
        cache_obj.to_hash == {}
        cache_obj.set("key1", "value1", 5)
        cache_obj.get("key1", 5).should == "value1"
        cache_obj.flush
        cache_obj.to_hash.should == {}
      end

      it "should wipe out internal hash when it has no data" do
        cache_obj.to_hash.should == {}
      end
    end

    pending "expire" do

      it "should run without error" do
        cache_obj.expire
      end

      it "should expire entries that are ready to be expired" do
        # Store a few objects that expire late
        cache_obj.set("key1", "value1", 3600)
        cache_obj.set("key2", "value2", 7200)

        # Store a few objects that expire earlier
        cache_obj.set("key3", "value3", 1)
        cache_obj.set("key4", "value4", 60)

        # Wind forward time
        now = Time.now
        Time.stubs(:now).returns(now + 1800)

        # Run expire
        cache_obj.expire

        # Get the raw hash to look at this
        cache_data = cache_obj.to_hash

        # Late expiring objects should be fine
        cache_data["key1"][:data].should == "value1"
        cache_data["key2"][:data].should == "value2"

        # Earlier expiring objects should be expired
        cache_data.has_key?("key3").should be_false
        cache_data.has_key?("key4").should be_false
      end

    end

  end

end
