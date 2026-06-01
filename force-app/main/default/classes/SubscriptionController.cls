/**
 * SubscriptionController
 * Handles subscription operations for employer portal
 */
public with sharing class SubscriptionController {
    
    @AuraEnabled(cacheable=true)
    public static SubscriptionWrapper getSubscription(Id accountId) {
        List<Employer_Subscription__c> subs = [
            SELECT Id, Subscription_Tier__c, Status__c, Trial_Start_Date__c,
                   Trial_End_Date__c, Subscription_Start_Date__c, Current_Period_End__c,
                   Monthly_Price__c, Cancel_At_Period_End__c, Features_Enabled__c
            FROM Employer_Subscription__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        if (subs.isEmpty()) {
            // Create default free subscription
            return createDefaultSubscription(accountId);
        }
        
        return new SubscriptionWrapper(subs[0]);
    }
    
    @AuraEnabled
    public static String createCheckoutSession(Id accountId, String priceId, String successUrl, String cancelUrl) {
        Account employer = [
            SELECT Id, Name, Stripe_Customer_ID__c
            FROM Account WHERE Id = :accountId
        ];
        
        Employer_Subscription__c sub = [
            SELECT Id, Billing_Email__c FROM Employer_Subscription__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        
        // Create Stripe customer if needed
        String customerId = employer.Stripe_Customer_ID__c;
        if (String.isBlank(customerId)) {
            customerId = StripeService.createCustomer(employer.Name, sub.Billing_Email__c);
            employer.Stripe_Customer_ID__c = customerId;
            update employer;
        }
        
        // Create checkout session
        StripeService.CheckoutSession session = StripeService.createCheckoutSession(
            customerId, priceId, successUrl, cancelUrl, accountId
        );
        
        return session.url;
    }
    
    @AuraEnabled
    public static String createPortalSession(Id accountId, String returnUrl) {
        Account employer = [SELECT Stripe_Customer_ID__c FROM Account WHERE Id = :accountId];
        
        if (String.isBlank(employer.Stripe_Customer_ID__c)) {
            throw new AuraHandledException('No billing account found. Please contact support.');
        }
        
        return StripeService.createPortalSession(employer.Stripe_Customer_ID__c, returnUrl);
    }
    
    @AuraEnabled
    public static void startFreeTrial(Id accountId) {
        Employer_Subscription__c sub = [
            SELECT Id, Status__c, Subscription_Tier__c, Trial_Start_Date__c
            FROM Employer_Subscription__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        
        if (sub.Trial_Start_Date__c != null) {
            throw new AuraHandledException('You have already used your free trial.');
        }
        
        sub.Subscription_Tier__c = 'Professional';
        sub.Status__c = 'Trial';
        sub.Trial_Start_Date__c = Date.today();
        sub.Trial_End_Date__c = Date.today().addDays(14);
        update sub;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Payment_Transaction__c> getPaymentHistory(Id accountId) {
        return [
            SELECT Id, Name, Amount__c, Currency__c, Status__c, 
                   Transaction_Date__c, Description__c, Invoice_PDF__c
            FROM Payment_Transaction__c
            WHERE Account__c = :accountId
            ORDER BY Transaction_Date__c DESC
            LIMIT 20
        ];
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getFeatureLimits(Id accountId) {
        String tier = SubscriptionService.getSubscriptionTier(accountId);
        
        Map<String, Object> limits = new Map<String, Object>();
        
        for (Feature_Flag__mdt feature : [
            SELECT DeveloperName, MasterLabel, Free_Tier_Enabled__c, Free_Tier_Limit__c,
                   Professional_Tier_Enabled__c, Professional_Tier_Limit__c
            FROM Feature_Flag__mdt WHERE Active__c = true
        ]) {
            Map<String, Object> featureInfo = new Map<String, Object>();
            
            if (tier == 'Free') {
                featureInfo.put('enabled', feature.Free_Tier_Enabled__c);
                featureInfo.put('limit', feature.Free_Tier_Limit__c);
            } else {
                featureInfo.put('enabled', feature.Professional_Tier_Enabled__c);
                featureInfo.put('limit', feature.Professional_Tier_Limit__c);
            }
            
            featureInfo.put('usage', SubscriptionService.getFeatureUsage(accountId, feature.DeveloperName));
            limits.put(feature.DeveloperName, featureInfo);
        }
        
        return limits;
    }
    
    private static SubscriptionWrapper createDefaultSubscription(Id accountId) {
        Contact primaryContact = [
            SELECT Email FROM Contact 
            WHERE AccountId = :accountId AND Is_Employer_User__c = true
            LIMIT 1
        ];
        
        Employer_Subscription__c sub = new Employer_Subscription__c(
            Account__c = accountId,
            Subscription_Tier__c = 'Free',
            Status__c = 'Active',
            Billing_Email__c = primaryContact?.Email
        );
        insert sub;
        
        return new SubscriptionWrapper(sub);
    }
    
    public class SubscriptionWrapper {
        @AuraEnabled public Id subscriptionId;
        @AuraEnabled public String tier;
        @AuraEnabled public String status;
        @AuraEnabled public Date trialEndDate;
        @AuraEnabled public Date periodEndDate;
        @AuraEnabled public Decimal monthlyPrice;
        @AuraEnabled public Boolean isTrialing;
        @AuraEnabled public Integer daysRemaining;
        @AuraEnabled public Boolean cancelAtPeriodEnd;
        
        public SubscriptionWrapper(Employer_Subscription__c sub) {
            this.subscriptionId = sub.Id;
            this.tier = sub.Subscription_Tier__c;
            this.status = sub.Status__c;
            this.trialEndDate = sub.Trial_End_Date__c;
            this.periodEndDate = sub.Current_Period_End__c;
            this.monthlyPrice = sub.Monthly_Price__c;
            this.cancelAtPeriodEnd = sub.Cancel_At_Period_End__c;
            this.isTrialing = sub.Status__c == 'Trial';
            
            if (this.isTrialing && sub.Trial_End_Date__c != null) {
                this.daysRemaining = Date.today().daysBetween(sub.Trial_End_Date__c);
            } else if (sub.Current_Period_End__c != null) {
                this.daysRemaining = Date.today().daysBetween(sub.Current_Period_End__c);
            }
        }
    }
}