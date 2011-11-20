#!/usr/bin/env rspec

require 'spec_helper'
require 'facter/util/cache/persistent_hash'
require 'yaml'

describe Facter::Util::Cache::PersistentHash do
  let(:cache_dir) {
    tmpdir
  }

  let(:cache_options) do
    {:path => cache_dir}
  end

  let(:cache) do
    described_class.new(cache_options)
  end

  it "should be a plugin subclass" do
    parent = Facter::Util::CachePlugin
    described_class.ancestors.include?(parent).should be_true
  end

  it "should allow instantiation" do
    described_class.new(cache_options)
  end

  context "get method" do
    it "should exist" do
      described_class.method_defined?(:get).should be_true
    end

    it "is called using a key" do
      cache.get("test")
    end
  end

  context "set method" do
    it "should exist" do
      described_class.method_defined?(:set).should be_true
    end

    it "is called using a key and value hash" do
      value = {:data => "value"}
      cache.set("key", value)
    end
  end

  context "delete method" do
    it "should exist" do
      described_class.method_defined?(:delete).should be_true
    end

    it "is called using a key" do
      cache.delete("key")
    end
  end

  context "clear method" do
    it "should exist" do
      described_class.method_defined?(:clear).should be_true
    end

    it "is called with no args" do
      cache.clear()
    end
  end

  it "should allow you to get a value you set" do
    value = {:data => "value"}
    cache.set("key", value)
    cache.get("key").should == value
  end

  it "should allow you to get a nil value you set" do
    value = {:data => nil}
    cache.set("key", value)
    cache.get("key").should == value
  end

  it "should allow you to delete a value you set" do
    value = {:data => "value"}
    cache.set("key", value)
    cache.get("key").should == value
    cache.delete("key")
    cache.get("key").should == nil
  end

  it "should allow you to clear all values" do
    value = {:data => "value"}
    cache.set("key", value)
    cache.get("key").should == value
    cache.clear()
    cache.get("key").should == nil
  end

  it "a get should grab the mtime of the file" do
    cache.expects(:cache_file_mtime)
    cache.get("key")
  end

  context "when cache dir is not readable or writeable" do
    before :each do
      Kernel.stubs(:warn)
      File.chmod(0000, cache_dir)
    end

    after :each do
      File.chmod(0755, cache_dir)
    end

    it "using the memory cache should still work" do
      cache.set("key", "value")
      cache.get("key").should == "value"
    end

    it "should return a warning when setting and getting" do
      Facter.expects(:warnonce).with(
        regexp_matches(/^Cannot write to cache path /))

      cache.set("key", "value")
      cache.get("key").should == "value"
    end
  end

  context "when cache dir doesn't exist" do
    before :each do
      Kernel.stubs(:warn)
      Dir.rmdir(cache_dir)
    end

    it "using the memory cache should still work" do
      cache.set("key", "value")
      cache.get("key").should == "value"
    end

    it "should return a warning" do
      # Stub kernel warn so we don't get stdout messages from rspec
      Kernel.stubs(:warn)

      Facter.expects(:warnonce).with(
        regexp_matches(/^Cannot write to cache path /))

      cache.set("key", "value")
      cache.get("key").should == "value"
    end
  end

  context "when there is existing cache items" do
    before :each do
      FileUtils.cp Dir.glob("#{SPECDIR}/fixtures/cache/sample1/*"), cache_dir
    end

    it "should be able to retrieve existing values" do
      cache.get("macaddress").should == {
        "data"=>"sample_data",
        "ttl"=>0,
        "stored"=>1322429657,
        "key"=>"macaddress",
      }
    end

    it "should be able to overwrite existing values" do
      new_value = {
        "data"=>"new_data",
        "ttl"=>0,
        "stored"=>1322429665,
        "key"=>"macaddress",
      }

      cache.set("macaddress", new_value)
      File.open(cache.cache_file("macaddress"), "r") do |f|
        f.read.should == <<-EOS
--- 
ttl: 0
data: new_data
stored: 1322429665
key: macaddress
        EOS
      end
      cache.get("macaddress").should == new_value
    end
  end

  it "should grab the entry from the filesystem if its mtime is newer" do
    old_value = {
      "data" => "old_data",
      "ttl" => 0,
      "stored" => 1200000000,
      "key" => "monkey",
    }
    cache.set("monkey", old_value)
    cache.get("monkey").should == old_value

    new_value = old_value.dup
    new_value["data"] = "new_data"
    File.open(cache.cache_file("monkey"), "w") do |f|
      f.write(new_value.to_yaml)
    end
    # Do this artificially since ruby doesn't support microsecond resolution
    # for stat
    cache.expects(:cache_file_mtime).with("monkey").returns(Time.now + 200)
    cache.get("monkey").should == new_value
  end

  it "shouldn't grab the entry from the filesystem if mtime hasn't changed" do
    value = {
      "data" => "old_data",
      "ttl" => 0,
      "stored" => 1200000000,
      "key" => "monkey",
    }
    cache.set("monkey", value)
    cache.get("monkey").should == value

    cache.expects(:load_file).never

    cache.get("monkey").should == value
  end
end
