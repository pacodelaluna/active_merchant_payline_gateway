module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    module Integrations #:nodoc:
      module Payline
        class Return < ActiveMerchant::Billing::Integrations::Return
          
          def success?
            
          end

          def error
            params[:result][:code]
          end

          def error_description
            params[:result][:short_message]
          end
          
        end
      end
    end
  end
end