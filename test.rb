# This file is a DRY way to set all of the requirements
# that our tests will need, as well as a before statement
# that purges the database and creates fixtures before every test

ENV['APP_ENV'] = 'test'
require 'simplecov'
SimpleCov.start
require 'minitest/autorun'
require './app'
require 'pry-byebug'

def app
  Sinatra::Application
end

def publish_tweet(tweet)
  RABBIT_EXCHANGE.publish(tweet, routing_key: NEW_TWEET.name)
  sleep 3
end

describe 'NanoTwitter Searcher' do
  include Rack::Test::Methods
  before do
    REDIS.flushall
    SEARCH_HTML.purge
    @tweet_id = 0
    @tweet_body = 'scalability is the best'
    @tweet = { tweet_id: @tweet_id, tweet_body: @tweet_body }.to_json
  end

  it 'can tokenize a single tweet' do
    parse_tweet_tokens(JSON.parse(@tweet))
    msg_json = JSON.parse SEARCH_HTML.pop.last
    msg_json['tweet_id'].must_equal 0
    @tweet_body.split.each do |token|
      msg_json['tokens'].include?(token).must_equal true
      REDIS.lrange(token, 0, -1).must_equal ['0']
    end
  end

  it 'can parse a tweet from the queue' do
    publish_tweet(@tweet)
    msg_json = JSON.parse SEARCH_HTML.pop.last
    msg_json['tweet_id'].must_equal 0
    @tweet_body.split.each do |token|
      msg_json['tokens'].include?(token).must_equal true
      REDIS.lrange(token, 0, -1).must_equal ['0']
    end
  end

  it 'is case-insensitive' do
    tweet2 = {
      tweet_id: 1,
      tweet_body: 'i love SCALABILITY'
    }.to_json
    publish_tweet(tweet2)
    msg_json = JSON.parse SEARCH_HTML.pop.last
    msg_json['tweet_id'].must_equal 1
    %w[i love scalability].each do |token|
      msg_json['tokens'].include?(token).must_equal true
      REDIS.lrange(token, 0, -1).must_equal ['1']
    end
  end

  it 'ignores punctuation' do
    tweet2 = {
      tweet_id: 1,
      tweet_body: 'i love scalability!'
    }.to_json
    publish_tweet(tweet2)
    msg_json = JSON.parse SEARCH_HTML.pop.last
    msg_json['tweet_id'].must_equal 1
    %w[i love scalability].each do |token|
      msg_json['tokens'].include?(token).must_equal true
      REDIS.lrange(token, 0, -1).must_equal ['1']
    end
  end

  it 'can seed multiple tweets' do
    payload = [{ tweet_id: 0, tweet_body: @tweet_body },
               { tweet_id: 1, tweet_body: 'i love scalability' }].to_json
    seed_from_payload(JSON.parse(payload))
    msg_json1 = JSON.parse SEARCH_HTML.pop.last
    msg_json1['tweet_id'].must_equal 0
    @tweet_body.split.each do |token|
      msg_json1['tokens'].include?(token).must_equal true
    end
    msg_json2 = JSON.parse SEARCH_HTML.pop.last
    msg_json2['tweet_id'].must_equal 1
    %w[i love scalability].each do |token|
      msg_json2['tokens'].include?(token).must_equal true
    end
    %w[is the best].each { |token| REDIS.lrange(token, 0, -1).must_equal ['0'] }
    %w[i love].each { |token| REDIS.lrange(token, 0, -1).must_equal ['1'] }
    REDIS.lrange('scalability', 0, -1).sort.must_equal %w[0 1]
  end

  it 'can seed multiple tweets from queue' do
    payload = [{ tweet_id: 0, tweet_body: @tweet_body },
               { tweet_id: 1, tweet_body: 'i love scalability' }].to_json
    RABBIT_EXCHANGE.publish(payload, routing_key: 'searcher.data.seed')
    sleep 3
    msg_json1 = JSON.parse SEARCH_HTML.pop.last
    msg_json1['tweet_id'].must_equal 0
    @tweet_body.split.each do |token|
      msg_json1['tokens'].include?(token).must_equal true
    end
    msg_json2 = JSON.parse SEARCH_HTML.pop.last
    msg_json2['tweet_id'].must_equal 1
    %w[i love scalability].each do |token|
      msg_json2['tokens'].include?(token).must_equal true
    end
    %w[is the best].each { |token| REDIS.lrange(token, 0, -1).must_equal ['0'] }
    %w[i love].each { |token| REDIS.lrange(token, 0, -1).must_equal ['1'] }
    REDIS.lrange('scalability', 0, -1).sort.must_equal %w[0 1]
  end

  it 'can get a second page of search results' do
    4.times { |i| parse_tweet_tokens(JSON.parse({tweet_id: i, tweet_body: 'scalability'}.to_json)) }
    resp = (get '/search?token=scalability&page_num=2&page_size=2').body
    JSON.parse(resp).count.must_equal 2
  end
end
