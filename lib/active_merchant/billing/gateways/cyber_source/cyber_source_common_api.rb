module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    # This module is included in both PaypalGateway and PaypalExpressGateway
    module CyberSourceCommonAPI
      
      TEST_URL = 'https://ics2wstest.ic3.com/commerce/1.x/transactionProcessor'
      LIVE_URL = 'https://ics2ws.ic3.com/commerce/1.x/transactionProcessor'
      
      # map credit card to the CyberSource expected representation
      CREDIT_CARD_CODES = {
        :visa  => '001',
        :master => '002',
        :american_express => '003',
        :discover => '004'
      } 

      # map response codes to something humans can read
      RESPONSE_CODES = {
        :r100 => "Successful transaction",
        :r101 => "Request is missing one or more required fields" ,
        :r102 => "One or more fields contains invalid data",
        :r150 => "General failure",
        :r151 => "The request was received but a server time-out occurred",
        :r152 => "The request was received, but a service timed out",
        :r200 => "The authorization request was approved by the issuing bank but declined by CyberSource because it did not pass the AVS check",
        :r201 => "The issuing bank has questions about the request",
        :r202 => "Expired card", 
        :r203 => "General decline of the card", 
        :r204 => "Insufficient funds in the account", 
        :r205 => "Stolen or lost card", 
        :r207 => "Issuing bank unavailable", 
        :r208 => "Inactive card or card not authorized for card-not-present transactions", 
        :r209 => "American Express Card Identifiction Digits (CID) did not match", 
        :r210 => "The card has reached the credit limit", 
        :r211 => "Invalid card verification number", 
        :r221 => "The customer matched an entry on the processor's negative file", 
        :r230 => "The authorization request was approved by the issuing bank but declined by CyberSource because it did not pass the card verification check", 
        :r231 => "Invalid account number",
        :r232 => "The card type is not accepted by the payment processor",
        :r233 => "General decline by the processor",
        :r234 => "A problem exists with your CyberSource merchant configuration",
        :r235 => "The requested amount exceeds the originally authorized amount",
        :r236 => "Processor failure",
        :r237 => "The authorization has already been reversed",
        :r238 => "The authorization has already been captured",
        :r239 => "The requested transaction amount must match the previous transaction amount",
        :r240 => "The card type sent is invalid or does not correlate with the credit card number",
        :r241 => "The request ID is invalid",
        :r242 => "You requested a capture, but there is no corresponding, unused authorization record.",
        :r243 => "The transaction has already been settled or reversed",
        :r244 => "The bank account number failed the validation check",
        :r246 => "The capture or credit is not voidable because the capture or credit information has already been submitted to your processor",
        :r247 => "You requested a credit for a capture that was previously voided",
        :r250 => "The request was received, but a time-out occurred with the payment processor",
        :r254 => "Your CyberSource account is prohibited from processing stand-alone refunds",
        :r255 => "Your CyberSource account is not configured to process the service in the country you specified" 
      }
      
      private

      def add_business_rules_data(xml)
        xml.tag! 'businessRules' do
          xml.tag!('ignoreAVSResult', 'true') if @options[:ignore_avs]
          xml.tag!('ignoreCVResult', 'true') if @options[:ignore_cvv]
        end 
      end

      # Create all address hash key value pairs so that we still function if we were only provided with one or two of them 
      def setup_address_hash(options)
        options[:billing_address] = options[:billing_address] || options[:address] || {}
        options[:shipping_address] = options[:shipping_address] || {}
      end
      
      def add_purchase_data(xml, money = 0, include_grand_total = false, options={})
        xml.tag! 'purchaseTotals' do
          xml.tag! 'currency', options[:currency] || currency(money)
          xml.tag!('grandTotalAmount', amount(money))  if include_grand_total 
        end
      end
      
      def add_purchase_service(xml, options)
        xml.tag! 'ccAuthService', {'run' => 'true'}
        xml.tag! 'ccCaptureService', {'run' => 'true'}
      end

      def add_address(xml, creditcard, address, options, shipTo = false)      
        xml.tag! shipTo ? 'shipTo' : 'billTo' do
          xml.tag! 'firstName', creditcard.first_name
          xml.tag! 'lastName', creditcard.last_name 
          xml.tag! 'street1', address[:address1]
          xml.tag! 'street2', address[:address2]
          xml.tag! 'city', address[:city]
          xml.tag! 'state', address[:state]
          xml.tag! 'postalCode', address[:zip]
          xml.tag! 'country', address[:country]
          xml.tag! 'email', options[:email]
        end 
      end

      def add_creditcard(xml, creditcard)      
        xml.tag! 'card' do
          xml.tag! 'accountNumber', creditcard.number
          xml.tag! 'expirationMonth', format(creditcard.month, :two_digits)
          xml.tag! 'expirationYear', format(creditcard.year, :four_digits)
          xml.tag!('cvNumber', creditcard.verification_value) unless (@options[:ignore_cvv] || creditcard.verification_value.blank? )
          xml.tag! 'cardType', CREDIT_CARD_CODES[card_brand(creditcard).to_sym]
        end
      end

      # Contact CyberSource, make the SOAP request, and parse the reply into a Response object
      def commit(request, options)
	      response = parse(ssl_post(test? ? TEST_URL : LIVE_URL, build_request(request, options)))
        
	      success = response[:decision] == "ACCEPT"
	      message = RESPONSE_CODES[('r' + response[:reasonCode]).to_sym] rescue response[:message] 
        authorization = success ? [ options[:order_id], response[:requestID], response[:requestToken] ].compact.join(";") : nil
        
        Response.new(success, message, response, 
          :test => test?, 
          :authorization => authorization,
          :avs_result => { :code => response[:avsCode] },
          :cvv_result => response[:cvCode]
        )
      end
      
      # Parse the SOAP response
      # Technique inspired by the Paypal Gateway
      def parse(xml)
        reply = {}
        xml = REXML::Document.new(xml)
        if root = REXML::XPath.first(xml, "//c:replyMessage")
          root.elements.to_a.each do |node|
            case node.name  
            when 'c:reasonCode'
              reply[:message] = reply(node.text)
            else
              parse_element(reply, node)
            end
          end
        elsif root = REXML::XPath.first(xml, "//soap:Fault") 
          parse_element(reply, root)
          reply[:message] = "#{reply[:faultcode]}: #{reply[:faultstring]}"
        end
        return reply
      end     

      def parse_element(reply, node)
        if node.has_elements?
          node.elements.each{|e| parse_element(reply, e) }
        else
          if node.parent.name =~ /item/
            parent = node.parent.name + (node.parent.attributes["id"] ? "_" + node.parent.attributes["id"] : '')
            reply[(parent + '_' + node.name).to_sym] = node.text
          else  
            reply[node.name.to_sym] = node.text
          end
        end
        return reply
      end
      
    end
  end
end
