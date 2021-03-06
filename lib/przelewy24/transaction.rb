require 'httparty'
require 'json'

module Przelewy24
  class Transaction
    attr_accessor :options
    attr_reader :token, :transaction_url

    def initialize(options = {})
      @conf = Przelewy24.config
      @options = p24_options(@conf.default_transaction_options).merge(p24_options(options))
    end

    def test_connection
      params = create_params @conf.test_connection_params
      sign params, %w(p24_pos_id)
      verify_params params
      response = query_p24 @conf.test_url, params
      response['error'] == '0'
    end

    def register_transaction
      params = create_params @conf.register_transaction_params
      unless @options[:p24_order_id].present?
        sign params, %w(p24_session_id p24_merchant_id p24_amount p24_currency)
        verify_params params
        response = query_p24 @conf.register_url, params
        @token = response['token']
        params.merge({:p24_token => @token})
      else
        @token = params[:p24_token]
      end
      @transaction_url = @conf.request_url + @token
    end

    def verify_transaction_status(params)
      test = [params[:p24_session_id],params[:p24_order_id],params[:p24_amount],params[:p24_currency],@conf.crc]
      raise 'malformed sign' unless Digest::MD5.hexdigest(test.join('|')) == params[:p24_sign]
      %i(p24_session_id p24_amount p24_currency).each do |t|
        raise "param #{t} not match" unless params[t].to_s == @options[t].to_s
      end
      @options[:p24_order_id] = params[:p24_order_id]
      true
    end

    def confirm_transaction
      params = create_params @conf.confirm_transaction_params
      sign params, %w(p24_session_id p24_order_id p24_amount p24_currency)
      verify_params params
      response = query_p24 @conf.confirm_transaction_url, params
      response['error'] == '0'
    end

    private

    attr_writer :conf

    def p24_options(options)
      out = {}
      options.each do |k, v|
        out[('p24_'+k.to_s).to_sym] = v
      end
      out[:p24_pos_id] = @conf.merchant_id unless out[:p24_pos_id].present?
      out[:p24_amount] = (out[:p24_amount]*100).to_int if out[:p24_amount].present?
      out
    end

    def query_p24(url, params)
      response = HTTParty.post url, body: params
      response = Rack::Utils.parse_nested_query response.parsed_response
      raise response['error']+': '+response['errorMessage'] unless response['error'] == '0'
      response
    end

    def verify_params(params)
      params.each do |p, v|
        raise "#{p} cannot be nil" unless v.present?
      end
    end

    def create_params(source_params = {})
      params = {}
      source_params.each do |k, v|
        params[k] = @options[k]
      end
      params
    end

    def sign(params, with_params = {})
      p = []
      with_params.each do |k|
        p << @options[k.to_sym]
      end
      p << @conf.crc
      s = Digest::MD5.hexdigest p.join('|')
      params[:p24_sign] = s
    end
  
  end
end
