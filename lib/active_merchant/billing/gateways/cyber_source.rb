require File.dirname(__FILE__) + '/cyber_source/cyber_source_common_api'
require File.dirname(__FILE__) + '/cyber_source/cyber_source_recurring_api'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    # See the remote and mocked unit test files for example usage.  Pay special attention to the contents of the options hash.
    #
    # Initial setup instructions can be found in http://cybersource.com/support_center/implementation/downloads/soap_api/SOAP_toolkits.pdf
    # 
    # Debugging 
    # If you experience an issue with this gateway be sure to examine the transaction information from a general transaction search inside the CyberSource Business
    # Center for the full error messages including field names.   
    #
    # Important Notes
    # * AVS and CVV only work against the production server.  You will always get back X for AVS and no response for CVV against the test server. 
    # * Nexus is the list of states or provinces where you have a physical presence.  Nexus is used to calculate tax.  Leave blank to tax everyone.  
    # * If you want to calculate VAT for overseas customers you must supply a registration number in the options hash as vat_reg_number. 
    # * productCode is a value in the line_items hash that is used to tell CyberSource what kind of item you are selling.  It is used when calculating tax/VAT.
    # * All transactions use dollar values.
    class CyberSourceGateway < Gateway
      include CyberSourceCommonAPI
      include CyberSourceRecurringApi
          
      # visa, master, american_express, discover
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]
      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.homepage_url = 'http://www.cybersource.com'
      self.display_name = 'CyberSource'

      # These are the options that can be used when creating a new CyberSource Gateway object.
      # 
      # :login =>  your username 
      #
      # :password =>  the transaction key you generated in the Business Center       
      #
      # :test => true   sets the gateway to test mode
      #
      # :vat_reg_number => your VAT registration number  
      #
      # :nexus => "WI CA QC" sets the states/provinces where you have a physical presense for tax purposes
      #
      # :ignore_avs => true   don't want to use AVS so continue processing even if AVS would have failed 
      #
      # :ignore_cvv => true   don't want to use CVV so continue processing even if CVV would have failed 
      def initialize(options = {})
        requires!(options, :login, :password)
        @options = options
        super
      end  

      # Should run against the test servers or not?
      def test?
        @options[:test] || Base.gateway_mode == :test
      end
      
      # Request an authorization for an amount from CyberSource 
      #
      # You must supply an :order_id in the options hash 
      def authorize(money, creditcard, options = {})
        requires!(options,  :order_id, :email)
        setup_address_hash(options)
        commit(build_auth_request(money, creditcard, options), options )
      end
      
      def auth_reversal(money, identification, options = {})
        commit(build_auth_reversal_request(money, identification, options), options)
      end

      # Capture an authorization that has previously been requested
      def capture(money, authorization, options = {})
        setup_address_hash(options)
        commit(build_capture_request(money, authorization, options), options)
      end

      # Purchase is an auth followed by a capture
      # You must supply an order_id in the options hash  
      def purchase(money, creditcard, options = {})
        requires!(options, :order_id, :email)
        setup_address_hash(options)
        commit(build_purchase_request(money, creditcard, options), options)
      end
      
      def void(identification, options = {})
        commit(build_void_request(identification, options), options)
      end

      def refund(money, identification, options = {})
        commit(build_credit_request(money, identification, options), options)
      end
      
      def credit(money, identification, options = {})
        deprecated CREDIT_DEPRECATION_MESSAGE
        refund(money, identification, options)
      end

      # CyberSource requires that you provide line item information for tax calculations
      # If you do not have prices for each item or want to simplify the situation then pass in one fake line item that costs the subtotal of the order
      #
      # The line_item hash goes in the options hash and should look like 
      # 
      #         :line_items => [
      #           {
      #             :declared_value => '1',
      #             :quantity => '2',
      #             :code => 'default',
      #             :description => 'Giant Walrus',
      #             :sku => 'WA323232323232323'
      #           },
      #           {
      #             :declared_value => '6',
      #             :quantity => '1',
      #             :code => 'default',
      #             :description => 'Marble Snowcone',
      #             :sku => 'FAKE1232132113123'
      #           }
      #         ]
      #
      # This functionality is only supported by this particular gateway may
      # be changed at any time
      def calculate_tax(creditcard, options)
        requires!(options,  :line_items)
        setup_address_hash(options)
        commit(build_tax_calculation_request(creditcard, options), options)	  
      end
      
      private                       
      
      def build_auth_request(money, creditcard, options)
        xml = Builder::XmlMarkup.new :indent => 2
        add_address(xml, creditcard, options[:billing_address], options)
        add_purchase_data(xml, money, true, options)
        add_creditcard(xml, creditcard)
        add_auth_service(xml)
        add_business_rules_data(xml)
        xml.target!
      end

      def build_tax_calculation_request(creditcard, options)
        xml = Builder::XmlMarkup.new :indent => 2
        add_address(xml, creditcard, options[:billing_address], options, false)
        add_address(xml, creditcard, options[:shipping_address], options, true)
        add_line_item_data(xml, options)
        add_purchase_data(xml, 0, false, options)
        add_tax_service(xml)
        add_business_rules_data(xml)
        xml.target!
      end
 
      def build_capture_request(money, authorization, options)
        order_id, request_id, request_token = authorization.split(";")
        options[:order_id] = order_id

        xml = Builder::XmlMarkup.new :indent => 2
        add_purchase_data(xml, money, true, options)
        add_capture_service(xml, request_id, request_token)
        add_business_rules_data(xml)
        xml.target!
      end 

      def build_purchase_request(money, creditcard, options)
        xml = Builder::XmlMarkup.new :indent => 2
        add_address(xml, creditcard, options[:billing_address], options)
        add_purchase_data(xml, money, true, options)
        add_creditcard(xml, creditcard)
        add_purchase_service(xml, options)
        add_business_rules_data(xml)
        xml.target!
      end
      
      def build_void_request(identification, options)
        order_id, request_id, request_token = identification.split(";")
        options[:order_id] = order_id
        
        xml = Builder::XmlMarkup.new :indent => 2
        add_void_service(xml, request_id, request_token)
        xml.target!
      end

      def build_auth_reversal_request(money, identification, options)
        order_id, request_id, request_token = identification.split(";")
        options[:order_id] = order_id
        xml = Builder::XmlMarkup.new :indent => 2
        add_purchase_data(xml, money, true, options)
        add_auth_reversal_service(xml, request_id, request_token)
        xml.target!
      end

      def build_credit_request(money, identification, options)
        order_id, request_id, request_token = identification.split(";")
        options[:order_id] = order_id
        
        xml = Builder::XmlMarkup.new :indent => 2
        add_purchase_data(xml, money, true, options)
        add_credit_service(xml, request_id, request_token)
        
        xml.target!
      end
      
      def add_line_item_data(xml, options)
        options[:line_items].each_with_index do |value, index|
          xml.tag! 'item', {'id' => index} do
            xml.tag! 'unitPrice', amount(value[:declared_value])  
            xml.tag! 'quantity', value[:quantity]
            xml.tag! 'productCode', value[:code] || 'shipping_only'
            xml.tag! 'productName', value[:description]
            xml.tag! 'productSKU', value[:sku]
          end
        end
      end
      
      def add_merchant_data(xml, options)
        xml.tag! 'merchantID', @options[:login]
        xml.tag! 'merchantReferenceCode', options[:order_id]
        xml.tag! 'clientLibrary' ,'Ruby Active Merchant'
        xml.tag! 'clientLibraryVersion',  '1.0'
        xml.tag! 'clientEnvironment' , 'Linux'
      end

      def add_tax_service(xml)
        xml.tag! 'taxService', {'run' => 'true'} do
          xml.tag!('nexus', @options[:nexus]) unless @options[:nexus].blank?
          xml.tag!('sellerRegistration', @options[:vat_reg_number]) unless @options[:vat_reg_number].blank?
        end
      end

      def add_auth_service(xml)
        xml.tag! 'ccAuthService', {'run' => 'true'} 
      end

      def add_capture_service(xml, request_id, request_token)
        xml.tag! 'ccCaptureService', {'run' => 'true'} do
          xml.tag! 'authRequestID', request_id
          xml.tag! 'authRequestToken', request_token
        end
      end
      
      def add_void_service(xml, request_id, request_token)
        xml.tag! 'voidService', {'run' => 'true'} do
          xml.tag! 'voidRequestID', request_id
          xml.tag! 'voidRequestToken', request_token
        end
      end

      def add_auth_reversal_service(xml, request_id, request_token)
        xml.tag! 'ccAuthReversalService', {'run' => 'true'} do
          xml.tag! 'authRequestID', request_id
          xml.tag! 'authRequestToken', request_token
        end
      end

      def add_credit_service(xml, request_id, request_token)
        xml.tag! 'ccCreditService', {'run' => 'true'} do
          xml.tag! 'captureRequestID', request_id
          xml.tag! 'captureRequestToken', request_token
        end
      end

      
      # Where we actually build the full SOAP request using builder
      def build_request(body, options)
        xml = Builder::XmlMarkup.new :indent => 2
          xml.instruct!
          xml.tag! 's:Envelope', {'xmlns:s' => 'http://schemas.xmlsoap.org/soap/envelope/'} do
            xml.tag! 's:Header' do
              xml.tag! 'wsse:Security', {'s:mustUnderstand' => '1', 'xmlns:wsse' => 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd'} do
                xml.tag! 'wsse:UsernameToken' do
                  xml.tag! 'wsse:Username', @options[:login]
                  xml.tag! 'wsse:Password', @options[:password], 'Type' => 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordText'
                end
              end
            end
            xml.tag! 's:Body', {'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema'} do
              xml.tag! 'requestMessage', {'xmlns' => 'urn:schemas-cybersource-com:transaction-data-1.32'} do
                add_merchant_data(xml, options)
                xml << body
              end
            end
          end
        xml.target! 
      end

    end 
  end 
end 
