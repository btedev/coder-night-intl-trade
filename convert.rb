#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'
require 'nokogiri'
require 'bigdecimal'

class Rate
  attr_accessor :from, :to, :conversion

  def initialize(attrs={})
    @from       = attrs[:from]
    @to         = attrs[:to]
    @conversion = attrs[:conversion]
  end

  def parse(doc)
    @from       = doc.css('from').text
    @to         = doc.css('to').text
    @conversion = BigDecimal.new(doc.css('conversion').text)
  end

  def self.load(rates_file)
    doc = Nokogiri::XML(File.open(rates_file))
    doc.xpath('//rate').map do |rate_xml|
      rate = new
      rate.parse(rate_xml)
      rate
    end
  end
end

class Transaction
  attr_accessor :store, :sku, :amount, :currency

  def initialize(store, sku, amount_cur)
    @store    = store
    @sku      = sku
    @amount   = BigDecimal.new(amount_cur.split(' ').first)
    @currency = amount_cur.split(' ').last
  end

  def self.load(txns_file)
    file = File.open(txns_file, 'r')
    file.readline
    file.map do |line|
      new(*line.chomp.split(','))
    end
  end
end

class Convert
  attr_accessor :rates

  def initialize
    BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_EVEN)
    @rates = []
  end

  def bankers_round(val)
    BigDecimal.new(val.to_s).round(2)
  end

  def conversions_to_usd(from_cur)
     direct_conversion(from_cur) || chained_conversion(from_cur)
  end

  def direct_conversion(from_cur)
    [conversion(from_cur, 'USD')] if conversion(from_cur, 'USD')
  end

  def chained_conversion(from_cur)
    sorted_rates = rates.select { |rate| rate.from != 'USD' }.sort do |a, b|
      a.from <=> from_cur
    end.map { |rate| [rate] }

    all_paths(sorted_rates).select do |rates_arr|
      rates_arr.first.from == from_cur && rates_arr.last.to == 'USD'
    end.sort { |a, b| a.length <=> b.length }.first
  end

  def all_paths(paths)
    changed = false
    paths.each do |left_arr|
      paths.each do |right_arr|
        if left_arr.last.to == right_arr.first.from && left_arr.last.from != right_arr.first.to
          left_arr << right_arr.first
          changed = true
        end
      end
    end

    changed ? all_paths(paths) : paths
  end

  def conversion(from_cur, to_cur)
    rates.find { |rate| rate.from == from_cur && rate.to == to_cur }
  end

  def convert(amount, txn_cur)
    return amount if txn_cur == 'USD'
    unrounded = conversions_to_usd(txn_cur).inject(amount) do |amt, rate|
      amt * rate.conversion
    end
    bankers_round(unrounded)
  end

  def total(trans_file, rates_file, sku)
    txns = Transaction.load(trans_file)
    @rates = Rate.load(rates_file)
    txns.select { |txn| txn.sku == sku }.inject(0) do |sum, txn|
      sum += convert(txn.amount, txn.currency)
    end
  end
end

if ARGV.size == 3
  trans_file, rates_file, sku = ARGV
  convert = Convert.new
  puts "%.2f" % convert.total(trans_file, rates_file, sku).to_s
else
  puts "Usage: convert.rb transactions_file rates_file sku"
end

