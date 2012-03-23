require File.dirname(__FILE__) + '/cyber_source_common_api'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    module CyberSourceRecurringApi
      # Create a recurring payment.
      #
      # This transaction creates a recurring payment profile
      # ==== Parameters
      #
      # * <tt>credit_card</tt> -- The CreditCard details for the transaction.
      # * <tt>options</tt> -- A hash of parameters.
      #
      # ==== Options
      #
      # * <tt>:frequency</tt> -- How often card should be charged (REQUIRED)
      # * <tt>:billing_address</tt> -- The description to appear in the profile (REQUIRED)
      # * <tt>:order_id</tt> -- ? (REQUIRED)
      # * <tt>:email</tt> -- ? (REQUIRED)
      def recurring(credit_card, options = {})
        requires!(options, [:frequency, "on-demand", "weekly", "bi-weekly", "semi-monthly", "quarterly", "quad-weekly", "semi-annually", "annually"], 
          :billing_address, :order_id, :email)
        requires!(options[:billing_address], :first_name, :last_name)
        setup_address_hash(options)
        commit(build_create_subscription_request(credit_card, options), options)
      end

      # Update a recurring payment's details.
      #
      # This transaction updates an existing Recurring Billing Profile
      # and the subscription must have already been created previously 
      # by calling +recurring()+. The ability to change certain
      # details about a recurring payment is dependent on transaction history
      # and the type of plan you're subscribed with paypal. Web Payment Pro
      # seems to have the ability to update the most field.
      #
      # ==== Parameters
      #
      # * <tt>options</tt> -- A hash of parameters.
      # * <tt>profile_id</tt> -- A string containing the +profile_id+ of the
      # recurring payment already in place for a given credit card. (REQUIRED)
      def update_recurring(profile_id, options={})
        raise_error_if_blank('profile_id', profile_id)
        opts = options.dup
        commit(build_update_subscription_request(profile_id, options), options)
      end
      
      # Bills outstanding amount to a recurring payment profile.
      #
      # ==== Parameters
      #
      # * <tt>profile_id</tt> -- A string containing the +profile_id+ of the
      # recurring payment already in place for a given credit card. (REQUIRED)
      # * <tt>money</tt> -- Amount to charge card stored in profile
      def bill_outstanding_amount(profile_id, money, options = {})
        raise_error_if_blank('profile_id', profile_id)
        raise_error_if_blank('money', money)
        commit(build_subscription_purchase_request(money, options), options)
      end

      private
      
      def raise_error_if_blank(field_name, field)
        raise ArgumentError.new("Missing required parameter: #{field_name}") if field.blank?
      end
      	
      def build_create_subscription_request(credit_card, options)
        xml = Builder::XmlMarkup.new :indent => 2
        add_address(xml, options[:billing_address], options)
        add_purchase_data(xml, options[:setup_fee], true, options)  
        add_creditcard(xml, credit_card)
        add_subscription(xml, options)
        add_subscription_create_service(xml, options)
        add_business_rules_data(xml)
        xml.target!
      end

      def build_update_subscription_request(identification, options)
        reference_code, subscription_id, request_token = identification.split(";")
        options[:subscription] ||= {}
        options[:subscription][:subscription_id] = subscription_id
        xml = Builder::XmlMarkup.new :indent => 2
        add_address(xml, options[:billing_address], options) unless options[:billing_address].blank?
        add_purchase_data(xml, options[:setup_fee], true, options) unless options[:setup_fee].blank?
        add_creditcard(xml, options[:credit_card]) if options[:credit_card]
        add_subscription(xml, options)
        add_subscription_update_service(xml, options)
        add_business_rules_data(xml)
        xml.target!
      end
      

      def build_subscription_purchase_request(money, identification, options)
        reference_code, subscription_id, request_token = identification.split(";")
        options[:subscription] ||= {}
        options[:subscription][:subscription_id] = subscription_id
        xml = Builder::XmlMarkup.new :indent => 2
        add_purchase_data(xml, money, true, options)
        add_subscription(xml, options)
        add_purchase_service(xml, options)
        add_business_rules_data(xml)
        xml.target!
      end 
      
      def add_subscription_create_service(xml, options)
        add_purchase_service(xml, options) if options[:setup_fee]
        xml.tag! 'paySubscriptionCreateService', {'run' => 'true'}      	
      end
      	
      def add_subscription_update_service(xml, options)
        add_purchase_service(xml, options) if options[:setup_fee]
        xml.tag! 'paySubscriptionUpdateService', {'run' => 'true'}
      end

      def add_subscription(xml, options, payment_source=nil)
        if payment_source
          xml.tag! 'subscription' do
            xml.tag! 'paymentMethod', "credit card"
          end
        end
        xml.tag! 'recurringSubscriptionInfo' do
          xml.tag! 'subscriptionID',    options[:subscription][:subscription_id]
          xml.tag! 'status',            options[:subscription][:status]                         if options[:subscription][:status]
          xml.tag! 'amount',            options[:subscription][:amount]                         if options[:subscription][:amount]        
          xml.tag! 'numberOfPayments',  options[:subscription][:occurrences]                    if options[:subscription][:occurrences]
          xml.tag! 'automaticRenew',    options[:subscription][:auto_renew]                     if options[:subscription][:auto_renew]
          xml.tag! 'frequency',         options[:subscription][:frequency]                      if options[:subscription][:frequency]
          xml.tag! 'startDate',         options[:subscription][:start_date].strftime("%Y%m%d")  if options[:subscription][:start_date]
          xml.tag! 'endDate',           options[:subscription][:end_date].strftime("%Y%m%d")    if options[:subscription][:end_date]
          xml.tag! 'approvalRequired',  options[:subscription][:approval_required] || false
          xml.tag! 'event',             options[:subscription][:event]                          if options[:subscription][:event]
          xml.tag! 'billPayment',       options[:subscription][:bill_payment]                   if options[:subscription][:bill_payment]
        end
      end

    end
  end
end
