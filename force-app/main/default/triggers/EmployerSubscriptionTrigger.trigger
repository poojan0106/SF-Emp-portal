/**
 * EmployerSubscriptionTrigger
 * Handles subscription status changes and feature access
 */
trigger EmployerSubscriptionTrigger on Employer_Subscription__c (after update) {
    
    List<Employer_Subscription__c> tierChanges = new List<Employer_Subscription__c>();
    List<Employer_Subscription__c> statusChanges = new List<Employer_Subscription__c>();
    
    for (Employer_Subscription__c sub : Trigger.new) {
        Employer_Subscription__c oldSub = Trigger.oldMap.get(sub.Id);
        
        if (sub.Subscription_Tier__c != oldSub.Subscription_Tier__c) {
            tierChanges.add(sub);
        }
        
        if (sub.Status__c != oldSub.Status__c) {
            statusChanges.add(sub);
        }
    }
    
    // Handle tier upgrades/downgrades
    if (!tierChanges.isEmpty()) {
        SubscriptionHandler.handleTierChanges(tierChanges);
    }
    
    // Handle status changes (cancelled, expired, etc.)
    if (!statusChanges.isEmpty()) {
        SubscriptionHandler.handleStatusChanges(statusChanges);
    }
}