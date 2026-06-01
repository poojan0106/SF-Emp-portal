public class SubscriptionHandler {
    
    public static void handleTierChanges(List<Employer_Subscription__c> subscriptions) {
        Set<Id> accountIds = new Set<Id>();
        for (Employer_Subscription__c sub : subscriptions) {
            accountIds.add(sub.Account__c);
        }
        
        // Update account subscription tier formula field will auto-update
        // Send notification emails
        for (Employer_Subscription__c sub : subscriptions) {
            if (sub.Subscription_Tier__c == 'Professional') {
                EmailService.sendUpgradeConfirmation(sub.Account__c);
            } else if (sub.Subscription_Tier__c == 'Free') {
                EmailService.sendDowngradeNotification(sub.Account__c);
            }
        }
    }
    
    public static void handleStatusChanges(List<Employer_Subscription__c> subscriptions) {
        for (Employer_Subscription__c sub : subscriptions) {
            switch on sub.Status__c {
                when 'Cancelled' {
                    EmailService.sendCancellationConfirmation(sub.Account__c);
                }
                when 'Past_Due' {
                    // Already handled in webhook
                }
                when 'Expired' {
                    // Downgrade to free
                    sub.Subscription_Tier__c = 'Free';
                }
            }
        }
    }
}