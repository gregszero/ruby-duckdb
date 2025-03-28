# frozen_string_literal: true

require 'date'
require 'time'
require_relative 'converter'

module DuckDB
  # The DuckDB::Appender encapsulates DuckDB Appender.
  #
  #   require 'duckdb'
  #   db = DuckDB::Database.open
  #   con = db.connect
  #   con.query('CREATE TABLE users (id INTEGER, name VARCHAR)')
  #   appender = con.appender('users')
  #   appender.append_row(1, 'Alice')
  #
  class Appender
    include DuckDB::Converter

    RANGE_INT16 = -32_768..32_767
    RANGE_INT32 = -2_147_483_648..2_147_483_647
    RANGE_INT64 = -9_223_372_036_854_775_808..9_223_372_036_854_775_807

    #
    # appends huge int value.
    #
    #   require 'duckdb'
    #   db = DuckDB::Database.open
    #   con = db.connect
    #   con.query('CREATE TABLE numbers (num HUGEINT)')
    #   appender = con.appender('numbers')
    #   appender
    #     .begin_row
    #     .append_hugeint(-170_141_183_460_469_231_731_687_303_715_884_105_727)
    #     .end_row
    #
    def append_hugeint(value)
      lower, upper = integer_to_hugeint(value)
      _append_hugeint(lower, upper)
    end

    #
    # appends unsigned huge int value.
    #
    #   require 'duckdb'
    #   db = DuckDB::Database.open
    #   con = db.connect
    #   con.query('CREATE TABLE numbers (num UHUGEINT)')
    #   appender = con.appender('numbers')
    #   appender
    #     .begin_row
    #     .append_hugeint(340_282_366_920_938_463_463_374_607_431_768_211_455)
    #     .end_row
    #
    def append_uhugeint(value)
      lower, upper = integer_to_hugeint(value)
      _append_uhugeint(lower, upper)
    end

    #
    # appends date value.
    #
    #   require 'duckdb'
    #   db = DuckDB::Database.open
    #   con = db.connect
    #   con.query('CREATE TABLE dates (date_value DATE)')
    #   appender = con.appender('dates')
    #   appender.begin_row
    #   appender.append_date(Date.today)
    #   # or
    #   # appender.append_date(Time.now)
    #   # appender.append_date('2021-10-10')
    #   appender.end_row
    #   appender.flush
    #
    def append_date(value)
      date = to_date(value)

      _append_date(date.year, date.month, date.day)
    end

    #
    # appends time value.
    #
    #   require 'duckdb'
    #   db = DuckDB::Database.open
    #   con = db.connect
    #   con.query('CREATE TABLE times (time_value TIME)')
    #   appender = con.appender('times')
    #   appender.begin_row
    #   appender.append_time(Time.now)
    #   # or
    #   # appender.append_time('01:01:01')
    #   appender.end_row
    #   appender.flush
    #
    def append_time(value)
      time = _parse_time(value)

      _append_time(time.hour, time.min, time.sec, time.usec)
    end

    #
    # appends timestamp value.
    #
    #   require 'duckdb'
    #   db = DuckDB::Database.open
    #   con = db.connect
    #   con.query('CREATE TABLE timestamps (timestamp_value TIMESTAMP)')
    #   appender = con.appender('timestamps')
    #   appender.begin_row
    #   appender.append_time(Time.now)
    #   # or
    #   # appender.append_time(Date.today)
    #   # appender.append_time('2021-08-01 01:01:01')
    #   appender.end_row
    #   appender.flush
    #
    def append_timestamp(value)
      time = to_time(value)

      _append_timestamp(time.year, time.month, time.day, time.hour, time.min, time.sec, time.nsec / 1000)
    end

    #
    # appends interval.
    # The argument must be ISO8601 duration format.
    # WARNING: This method is expremental.
    #
    #   require 'duckdb'
    #   db = DuckDB::Database.open
    #   con = db.connect
    #   con.query('CREATE TABLE intervals (interval_value INTERVAL)')
    #   appender = con.appender('intervals')
    #   appender
    #     .begin_row
    #     .append_interval('P1Y2D') # => append 1 year 2 days interval.
    #     .end_row
    #     .flush
    #
    def append_interval(value)
      value = Interval.to_interval(value)
      _append_interval(value.interval_months, value.interval_days, value.interval_micros)
    end

    #
    # appends value.
    #
    #   require 'duckdb'
    #   db = DuckDB::Database.open
    #   con = db.connect
    #   con.query('CREATE TABLE users (id INTEGER, name VARCHAR)')
    #   appender = con.appender('users')
    #   appender.begin_row
    #   appender.append(1)
    #   appender.append('Alice')
    #   appender.end_row
    #
    def append(value)
      case value
      when NilClass
        append_null
      when Float
        append_double(value)
      when Integer
        case value
        when RANGE_INT16
          append_int16(value)
        when RANGE_INT32
          append_int32(value)
        when RANGE_INT64
          append_int64(value)
        else
          append_hugeint(value)
        end
      when String
        blob?(value) ? append_blob(value) : append_varchar(value)
      when TrueClass, FalseClass
        append_bool(value)
      when Time
        append_timestamp(value)
      when Date
        append_date(value)
      when DuckDB::Interval
        append_interval(value)
      else
        raise(DuckDB::Error, "not supported type #{value} (#{value.class})")
      end
    end

    #
    # append a row.
    #
    #   appender.append_row(1, 'Alice')
    #
    # is same as:
    #
    #   appender.begin_row
    #   appender.append(1)
    #   appender.append('Alice')
    #   appender.end_row
    #
    def append_row(*args)
      begin_row
      args.each do |arg|
        append(arg)
      end
      end_row
    end

    private

    def blob?(value)
      value.instance_of?(DuckDB::Blob) || value.encoding == Encoding::BINARY
    end

    def to_date(value)
      case value
      when Date, Time
        value
      else
        begin
          Date.parse(value)
        rescue StandardError
          raise(ArgumentError, "Cannot parse argument `#{value}` to Date.")
        end
      end
    end

    def to_time(value)
      case value
      when Time
        value
      when Date
        value.to_time
      else
        begin
          Time.parse(value)
        rescue StandardError
          raise(ArgumentError, "Cannot parse argument `#{value}` to Time or Date.")
        end
      end
    end
  end
end
