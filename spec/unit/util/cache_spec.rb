#!/usr/bin/env ruby

require 'spec_helper'
require 'facter/util/cache'

describe Facter::Util::Cache do
  describe "during initialization" do
    it "should create a valid object" do
      cache_obj = Facter::Util::Cache.new
      cache_obj.class.should == Facter::Util::Cache
    end
  end

  describe "when using method" do
    let(:cache_obj) {
      Facter::Util::Cache.new
    }

    describe "set" do
      it "should accept a valid key and value without error" do
        cache_obj.set("key1", "value1")
      end

      it "should accept a valid key, value and ttl without error" do
        cache_obj.set("key1", "value1", 1)
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
                raise_error(TypeError, "key only accepts a String " \
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
                raise_error(TypeError, "value only accepts Strings, " \
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
              expect { cache_obj.get(valid_item) }.to_not(
                raise_error(TypeError)
              )
            end
          end
        end

        describe "should thrown an error when it is not valid," do
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
              expect { cache_obj.get(invalid_item) }.to(
                raise_error(TypeError, "key only accepts a String " \
                "when using the get method. It must be smaller then 256 " \
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
                raise_error(TypeError, "key only accepts a String when " \
                "using the set method. It must be smaller then 256 " \
                "characters and not be empty.")
              )
            end
          end
        end
      end
    end

    describe "flush" do
      it "should run without error" do
        cache_obj.flush
      end
    end

  end

end
