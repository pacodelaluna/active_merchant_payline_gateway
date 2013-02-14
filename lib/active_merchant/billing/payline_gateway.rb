require 'savon'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:

    class PaylineGateway < Gateway

      self.supported_countries = ['FR']
      self.supported_cardtypes = [:visa, :master]
      self.homepage_url = 'http://www.payline.com'
      self.display_name = 'Payline'

      def initialize(options = {})
        requires!(options, :merchant_id, :access_key, :vad_id)
        @options = options
        super
      end

      def init_options
        return @options
      end

      def endpoint_url
        init_options[:test_mode] ? 'https://homologation.payline.com/V4/services/DirectPaymentAPI' : 'https://services.payline.com/V4/services/DirectPaymentAPI'
      end

      def authorize(money, credit_card, options = {})
        post = {}
        add_payment(post, amount(money), '100')
        add_credit_card(post, credit_card)
        add_order(post, amount(money), options)

        commit(:do_authorization, post, ["00000"], options)
      end

      def purchase(money, credit_card, options = {})
        post = {}
        add_payment(post, amount(money), '101')
        add_credit_card(post, credit_card)
        add_order(post, amount(money), options)

        commit(:do_authorization, post, ["00000"], options)
      end

      def recurring(money, credit_card_or_reference, options = {})
        # 01913 => Transaction Already Existing
        resp = store(credit_card_or_reference, options)
        if resp.success?
          post = {}
          add_payment(post, amount(money), '101')
          add_credit_card(post, credit_card_or_reference)
          add_order(post, amount(money), options)
          add_wallet_id(post, options)
          doing_recurrent(post, options)

          resp = commit(:do_recurrent_wallet_payment, post, ["02500", "02501"], options)
        end
        return resp
      end

      def credit(money, credit_card_or_reference, options = {})
        
      end

      def refund(money, reference, options = {})
        
      end

      def capture(money, reference, options = {})
        
      end

      def void(reference, options = {})
        
      end

      def store(credit_card_or_reference, options = {})
        post = {}
        add_wallet(post, credit_card_or_reference, options)
        resp = commit(:create_wallet, post, ["02500"], options)
        # => #WalletExisting #CardExisting
        if ["02502", "02521"].include?(resp.params['result'][:code])
          resp = commit(:update_wallet, post, ["02500", "02521"], options)
        end
        return resp
      end

      def unstore(reference, options = {})
        post = {}
        check_wallet(post, options)
        
        commit(:disable_wallet, post, ["02500"], options)
      end

      def verify(options = {})
       
      end

      private

      def amount(money)
        return money.to_i
      end

      def add_order(post, amount, options={})
        post.merge!({ :order => {
            :ref => "#{options[:order_id].to_s}_#{Time.now.strftime('%d/%m/%Y@%H:%M')}",
            :amount => amount.to_s,
            :currency => '978',
            :date => Time.now.strftime('%d/%m/%Y %H:%M')
          }
        })
      end

      def add_payment(post, amount, action, options={})
        post.merge!({ :payment => {
            :amount => amount.to_s,
            :currency => '978',
            :action => action,
            :mode => 'CPT',   
            :contractNumber => init_options[:vad_id]
          }
        })
      end

      def add_credit_card(post, credit_card)
        post.merge!({ :card => {
              :number => credit_card.number,
              :type => (credit_card.brand || 'visa').to_s.upcase,
              :expirationDate => ((credit_card.month.to_i<10 ? "0#{credit_card.month.to_s}" : credit_card.month.to_s)+credit_card.year[2..4]),
              :cvx => credit_card.verification_value,
              :cardholder => credit_card.first_name.to_s+' '+credit_card.last_name.to_s
            }
        })
      end

      def add_transaction(post, transaction_id)
        post[:transactionID] = transaction_id
      end

      def add_wallet(post, credit_card, options)
        post.merge!({ :wallet => {
              :walletId => options[:user_id],
              :lastName => options[:user_lastname],
              :firstName => options[:user_lastname],
              :card => {
                    :number => credit_card.number,
                    :type => (credit_card.brand.to_s || 'visa').upcase,
                    :expirationDate => ((credit_card.month.to_i<10 ? "0#{credit_card.month.to_s}" : credit_card.month.to_s)+credit_card.year[2..4]),
                    :cvx => credit_card.verification_value,
                    :cardholder => credit_card.first_name.to_s+' '+credit_card.last_name.to_s
                },
            },
            :contractNumber => init_options[:vad_id]
        })
      end

      def add_wallet_id(post, options)
        post.merge!({
            :walletId => options[:user_id]
        })
      end

      def check_wallet(post, options)
        post.merge!({
            :contractNumber => init_options[:vad_id],
            :walletId => options[:user_id]
        })
      end

      def doing_recurrent(post, options = {})
        # Implemented for "3 fois sans frais sur 2 mois" style
        amount = post[:payment][:amount].to_i
        first_amount = amount.modulo(options[:number]) == 1 ? (amount / options[:number]).round + 1 : (amount / options[:number]).round
        other_amount = amount.modulo(options[:number]) == 2 ? (amount / options[:number]).round + 1 : (amount / options[:number]).round
        #
        post[:payment][:mode] = "NX"
        post.merge!({ :recurring => {
              :firstAmount => first_amount,
              :amount => other_amount,
              :billingCycle => options[:cycle],
              :billingLeft => options[:number]
            }
        })
      end

      def commit(action, params, success_code, options)
        begin
          client = Savon.client do |wsdl, http|
            wsdl.document = "#{Rails.root}/config/payline/DirectPaymentAPI.wsdl.xml"
            wsdl.endpoint = self.endpoint_url
            http.auth.basic init_options[:merchant_id], init_options[:access_key]
          end
          response = client.request(action) do
            soap.body = params
          end
        rescue Exception => e
          raise "Problem Connection with Payline Gateway : #{e.inspect}"
        end
        p "================ #{response.inspect}"
        return build_response(
            response.body["#{action.to_s}_response".to_sym].merge!({ :action => "#{action.to_s}_response" }), 
            success_code, 
            options
        )
      end

      def build_response(server_response, success_code, options = {})
        Response.new(
          success_code.include?(server_response[:result][:code]), 
          server_response[:result][:short_message], 
          server_response,
          success_code.include?(server_response[:result][:code]) ? options.merge!(response_to_options(server_response)) : options
        )
      end

      def response_to_options(response)
        # To tune up to your need actually ...
        result = {}
        result.merge!({ :authorization => response[:authorization][:number]+'_'+response[:transaction][:id] }) if ["do_authorization_response"].include?(response[:action])
        result.merge!({ :authorization => response[:payment_record_id] }) if ["do_recurrent_wallet_payment_response"].include?(response[:action])
        result
      end

    end
  end
end
