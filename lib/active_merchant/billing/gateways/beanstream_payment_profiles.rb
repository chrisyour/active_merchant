module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class BeanstreamPaymentProfilesGateway < Gateway
      API_VERSION = '1.0'
      
      PROFILE_URL = 'https://www.beanstream.com/scripts/payment_profile.asp'
      PURCHASE_URL = 'https://www.beanstream.com/scripts/process_transaction.asp'
      
      self.supported_countries = ['CA']
      self.supported_cardtypes = [:visa, :master, :american_express]
      self.homepage_url = 'http://www.beanstream.com/'
      self.display_name = 'Beanstream.com'
      
      PROFILE_ACTIONS = {
        :new => 'N',
        :update => 'M'
      }
      
      CVD_CODES = {
        '1' => 'M',
        '2' => 'N',
        '3' => 'I',
        '4' => 'S',
        '5' => 'U',
        '6' => 'P'
      }

      AVS_CODES = {
        '0' => 'R',
        '5' => 'I',
        '9' => 'I'
      }
      
      # Creates a new BeanStreamPaymentProfilesGateway
      #
      # The gateway requires that a valid login, passcode, username, and password be passed
      # in the +options+ hash.
      #
      # ==== Options
      #
      # * <tt>:login</tt> -- The BeanStream Merchant ID found in Administration -> Company Info (REQUIRED)
      # * <tt>:passcode</tt> -- The BeanStream API access passcode set in Configuration -> Payment Profile Configuration. (REQUIRED)
      # * <tt>:username</tt> -- The BeanStream username set in Administration -> Account Settings -> Order Settings. (REQUIRED)
      # * <tt>:password</tt> -- The BeanStream password set in Administration -> Account Settings -> Order Settings. (REQUIRED)
      def initialize(options = {})
        requires!(options, :login, :passcode, :username, :password)
        @options = options
        super
      end
      
      # Creates a new payment profile
      #
      # An :order hash can be passed in the +options+ hash in order to store customer details such as name, email, phone, address, etc.
      # The :customer token can be passed in the +options+ hash when updating a payment profile.
      # A :custom hash containing :ref_1..:ref_5 values that will be kept with the payment profile.
      #
      # ==== Parameters
      #
      # * <tt>:credit_card</tt> -- An ActiveMerchant CreditCard object (OPTIONAL only when updating a profile)
      # 
      # ==== Options
      # 
      # * <tt>:order</tt> -- A hash that contains customer info (:name, :email, :phone, :address, :address_2, :city, :province, :country, or :postal_code) (OPTIONAL)
      # * <tt>:custom</tt> -- A hash that contains up to five custom values to store in the payment profile (:ref_1, :ref_2, :ref_3, :ref_4, :ref_5)
      # * <tt>:customer</tt> -- When updating an existing payment profile, include the unique customer code (REQUIRED when updating a payment profile)
      # 
      def profile(credit_card=nil, options={})
        options[:credit_card] = credit_card
        
        request = build_profile_request(options)
        request
      end
      
      # Processes a payment using an existing payment profile
      #
      # ==== Parameters
      #
      # * <tt>:amount</tt> -- Amount of the purchase in cents (REQUIRED)
      # * <tt>:customer</tt> -- The payment profile's customer code to make the purchase against (REQUIRED)
      #
      def purchase(amount, customer)
        options = {}
        options[:amount] = amount
        options[:customer] = customer
        
        request = build_purchase_request(options)
        request
      end
      
      private
      
      def build_profile_request(options)
        post = {}
        
        action = (options[:customer] == nil) ? :new : :update
        
        add_operation(post, action)
        add_customer(post, options) if action == :update
        add_credit_card(post, options)
        add_order(post, options)
        add_custom(post, options)
        
        profile_commit(post)
      end
      
      def build_purchase_request(options)
        post = {}

        add_amount(post, options[:amount])
        add_customer(post, options)
        
        purchase_commit(post)
      end
      
      def add_operation(post, action)
        unless PROFILE_ACTIONS.include?(action)
          raise StandardError, "Invalid Action: #{action}"
        end
        post[:operationType] = PROFILE_ACTIONS[action]
      end
      
      def add_amount(post, money)
        post[:trnAmount] = amount(money)
      end
      
      def add_customer(post, options)
        post[:customerCode] = options[:customer]
      end
      
      def add_credit_card(post, options)
        if options[:credit_card].nil?
          post
        else
          post[:trnCardOwner]   = options[:credit_card].name
          post[:trnCardNumber]  = options[:credit_card].number
          post[:trnExpMonth]    = format(options[:credit_card].month, :two_digits)
          post[:trnExpYear]     = format(options[:credit_card].year, :two_digits)
          post[:trnCardCvd]     = options[:credit_card].verification_value
        end
      end
      
      def add_order(post, options)
        if options[:order].nil?
          post
        else
          post[:ordName]          = options[:order][:name]
          post[:ordAddress1]      = options[:order][:address]
          post[:ordAddress2]      = options[:order][:address_2]
          post[:ordCity]          = options[:order][:city]
          post[:ordProvince]      = options[:order][:province]
          post[:ordCountry]       = options[:order][:country]
          post[:ordPostalCode]    = options[:order][:postal_code]
          post[:ordEmailAddress]  = options[:order][:email]
          post[:ordPhoneNumber]   = options[:order][:phone]
        end
      end
      
      def add_custom(post, options)
        if options[:custom].nil?
          post
        else
          post[:ref1]             = options[:custom][:ref_1]
          post[:ref2]             = options[:custom][:ref_2]
          post[:ref3]             = options[:custom][:ref_3]
          post[:ref4]             = options[:custom][:ref_4]
          post[:ref5]             = options[:custom][:ref_5]
        end
      end
      
    # Profile Commit Methods
      def profile_commit(post)
        profile_post(profile_post_data(post))
      end
      
      def profile_post_data(post)
        post[:responseFormat] = 'QS'
        post[:serviceVersion] = API_VERSION
        post[:merchantId]     = @options[:login]
        post[:passCode]       = @options[:passcode]
        
        post.reject{|k, v| v.blank?}.collect { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join("&")
      end
      
      def profile_post(data)
        response = parse(ssl_post(PROFILE_URL, data))
        
        build_response(success?(response), message(response), response,
          :test => test?,
        )
      end
      
    # Purchase Commit Methods
      def purchase_commit(post)
        purchase_post(purchase_post_data(post))
      end
      
      def purchase_post_data(post)
        post[:responseFormat] = 'QS'
        post[:requestType]    = 'BACKEND'
        post[:merchant_id]    = @options[:login]
        post[:passCode]       = @options[:passcode]
        post[:username]       = @options[:username]
        post[:password]       = @options[:password]
        
        post.reject{|k, v| v.blank?}.collect { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join("&")
      end
      
      def purchase_post(data)
        response = parse(ssl_post(PURCHASE_URL, data))
        
        build_response(success?(response), message(response), response,
          :test => test?,
          :authorization => authorization(response),
          :cvv_result => CVD_CODES[response[:cvdId]],
          :avs_result => { :code => (AVS_CODES.include? response[:avsId]) ? AVS_CODES[response[:avsId]] : response[:avsId] }
        )
      end
    
    # Shared Methods
      def parse(body)
        results = {}
        if !body.nil?
          body.split(/&/).each do |pair|
            key,val = pair.split('=')
            results[key.to_sym] = val.nil? ? nil : CGI.unescape(val)
          end
        end
        
        # Clean up the message text if there is any
        if results[:messageText]
          results[:messageText].gsub!(/<LI>/, "")
          results[:messageText].gsub!(/(\.)?<br>/, ". ")
          results[:messageText].strip!
        end
        
        results
      end
      
      def success?(response)
        response[:responseCode] == '1' || response[:trnApproved] == '1'
      end
      
      def test?
        (ActiveMerchant::Billing::Base.mode == :test) ? true : false
      end
      
      def message(response)
        response[:responseMessage] || response[:messageText]
      end
      
      def authorization(response)
        "#{response[:trnId]};#{response[:trnAmount]};#{response[:trnType]}"
      end
      
      def build_response(*args)
        Response.new(*args)
      end
    end
  end
end
