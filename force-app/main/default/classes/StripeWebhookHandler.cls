/**
 * StripeWebhookHandler
 * REST endpoint for Stripe webhook events
 */
@RestResource(urlMapping='/stripe/webhook/*')
global with sharing class StripeWebhookHandler {
    
    @HttpPost
    global static void handleWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            // Verify webhook signature
            String signature = req.headers.get('Stripe-Signature');
            String payload = req.requestBody.toString();
            
            if (!StripeService.verifyWebhookSignature(payload, signature)) {
                res.statusCode = 401;
                res.responseBody = Blob.valueOf('Invalid signature');
                return;
            }
            
            // Parse event
            Map<String, Object> event = (Map<String, Object>) JSON.deserializeUntyped(payload);
            String eventType = (String) event.get('type');
            Map<String, Object> data = (Map<String, Object>) event.get('data');
            Map<String, Object> object_x = (Map<String, Object>) data.get('object');
            
            // Route to handler
            switch on eventType {
                when 'checkout.session.completed' {
                    handleCheckoutCompleted(object_x);
                }
                when 'customer.subscription.updated' {
                    handleSubscriptionUpdated(object_x);
                }
                when 'customer.subscription.deleted' {
                    handleSubscriptionDeleted(object_x);
                }
                when 'invoice.payment_succeeded' {
                    handlePaymentSucceeded(object_x);
                }
                when 'invoice.payment_failed' {
                    handlePaymentFailed(object_x);
                }
            }
            
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('OK');
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Stripe webhook error: ' + e.getMessage());
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(e.getMessage());
        }
    }
    
    private static void handleCheckoutCompleted(Map<String, Object> session) {
        String customerId = (String) session.get('customer');
        String subscriptionId = (String) session.get('subscription');
        String accountId = (String) ((Map<String, Object>) session.get('metadata')).get('account_id');
        
        // Update subscription record
        Employer_Subscription__c sub = [
            SELECT Id, Account__c
            FROM Employer_Subscription__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        sub.Stripe_Customer_ID__c = customerId;
        sub.Stripe_Subscription_ID__c = subscriptionId;
        sub.Subscription_Tier__c = 'Professional';
        sub.Status__c = 'Active';
        sub.Subscription_Start_Date__c = Date.today();
        
        update sub;
        
        // Send confirmation email
        EmailService.sendSubscriptionConfirmation(sub.Account__c);
    }
    
    private static void handleSubscriptionUpdated(Map<String, Object> subscription) {
        String subscriptionId = (String) subscription.get('id');
        String status = (String) subscription.get('status');
        
        Employer_Subscription__c sub = [
            SELECT Id
            FROM Employer_Subscription__c
            WHERE Stripe_Subscription_ID__c = :subscriptionId
        ];
        
        // Map Stripe status to our status
        sub.Status__c = mapStripeStatus(status);
        sub.Cancel_At_Period_End__c = (Boolean) subscription.get('cancel_at_period_end');
        
        // Update period end
        Long periodEnd = (Long) subscription.get('current_period_end');
        sub.Current_Period_End__c = DateTime.newInstance(periodEnd * 1000).date();
        
        update sub;
    }
    
    /**
     * Handle subscription deletion/cancellation from Stripe
     */
    private static void handleSubscriptionDeleted(Map<String, Object> subscription) {
        String subscriptionId = (String) subscription.get('id');
        
        List<Employer_Subscription__c> subs = [
            SELECT Id, Account__c
            FROM Employer_Subscription__c
            WHERE Stripe_Subscription_ID__c = :subscriptionId
        ];
        
        if (!subs.isEmpty()) {
            Employer_Subscription__c sub = subs[0];
            sub.Status__c = 'Cancelled';
            sub.Cancellation_Date__c = Date.today();
            sub.Cancel_At_Period_End__c = false;
            update sub;
            
            // Send cancellation confirmation email
            EmailService.sendSubscriptionCancellation(sub.Account__c);
        }
    }
    
    private static void handlePaymentSucceeded(Map<String, Object> invoice) {
        String customerId = (String) invoice.get('customer');
        
        Account employer = [
            SELECT Id FROM Account 
            WHERE Stripe_Customer_ID__c = :customerId
        ];
        
        // Create payment record
        Payment_Transaction__c payment = new Payment_Transaction__c(
            Account__c = employer.Id,
            Stripe_Invoice_ID__c = (String) invoice.get('id'),
            Stripe_Payment_Intent_ID__c = (String) invoice.get('payment_intent'),
            Amount__c = ((Decimal) invoice.get('amount_paid')) / 100,
            Currency__c = ((String) invoice.get('currency')).toUpperCase(),
            Status__c = 'Succeeded',
            Transaction_Date__c = DateTime.now(),
            Invoice_PDF__c = (String) invoice.get('invoice_pdf')
        );
        insert payment;
    }
    
    private static void handlePaymentFailed(Map<String, Object> invoice) {
        String customerId = (String) invoice.get('customer');
        
        Account employer = [
            SELECT Id FROM Account 
            WHERE Stripe_Customer_ID__c = :customerId
        ];
        
        Employer_Subscription__c sub = [
            SELECT Id, Failed_Payment_Count__c
            FROM Employer_Subscription__c
            WHERE Account__c = :employer.Id
        ];
        
        sub.Failed_Payment_Count__c = (sub.Failed_Payment_Count__c ?? 0) + 1;
        sub.Status__c = 'Past_Due';
        update sub;
        
        // Create failed payment record
        Payment_Transaction__c payment = new Payment_Transaction__c(
            Account__c = employer.Id,
            Stripe_Invoice_ID__c = (String) invoice.get('id'),
            Amount__c = ((Decimal) invoice.get('amount_due')) / 100,
            Status__c = 'Failed',
            Failure_Reason__c = getFailureReason(invoice),
            Transaction_Date__c = DateTime.now()
        );
        insert payment;
        
        // Send payment failed email
        EmailService.sendPaymentFailedNotification(employer.Id);
    }
    
    private static String mapStripeStatus(String stripeStatus) {
        Map<String, String> statusMap = new Map<String, String>{
            'active' => 'Active',
            'trialing' => 'Trial',
            'past_due' => 'Past_Due',
            'canceled' => 'Cancelled',
            'unpaid' => 'Past_Due'
        };
        return statusMap.get(stripeStatus) ?? 'Active';
    }
    
    /**
     * Extract failure reason from Stripe invoice object
     */
    private static String getFailureReason(Map<String, Object> invoice) {
        // Try to get the failure message from payment intent
        Object paymentIntent = invoice.get('payment_intent');
        if (paymentIntent instanceof Map<String, Object>) {
            Map<String, Object> pi = (Map<String, Object>) paymentIntent;
            Object lastError = pi.get('last_payment_error');
            if (lastError instanceof Map<String, Object>) {
                Map<String, Object> error = (Map<String, Object>) lastError;
                String message = (String) error.get('message');
                if (String.isNotBlank(message)) {
                    return message;
                }
                // Fall back to decline code
                String declineCode = (String) error.get('decline_code');
                if (String.isNotBlank(declineCode)) {
                    return mapDeclineCode(declineCode);
                }
            }
        }
        
        // Try charge object if available
        Object charge = invoice.get('charge');
        if (charge instanceof Map<String, Object>) {
            Map<String, Object> chargeMap = (Map<String, Object>) charge;
            String failureMessage = (String) chargeMap.get('failure_message');
            if (String.isNotBlank(failureMessage)) {
                return failureMessage;
            }
        }
        
        return 'Payment failed';
    }
    
    /**
     * Map Stripe decline codes to user-friendly messages
     */
    private static String mapDeclineCode(String declineCode) {
        Map<String, String> declineMessages = new Map<String, String>{
            'insufficient_funds' => 'Insufficient funds',
            'lost_card' => 'Card reported lost',
            'stolen_card' => 'Card reported stolen',
            'expired_card' => 'Card has expired',
            'incorrect_cvc' => 'Incorrect security code',
            'processing_error' => 'Processing error - please try again',
            'incorrect_number' => 'Incorrect card number',
            'card_declined' => 'Card was declined',
            'card_not_supported' => 'Card type not supported',
            'currency_not_supported' => 'Currency not supported',
            'duplicate_transaction' => 'Duplicate transaction',
            'fraudulent' => 'Transaction flagged as potentially fraudulent'
        };
        return declineMessages.containsKey(declineCode) 
            ? declineMessages.get(declineCode) 
            : 'Card declined: ' + declineCode;
    }
}