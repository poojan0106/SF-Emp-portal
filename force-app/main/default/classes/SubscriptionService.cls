/**
 * SubscriptionService
 * Core subscription logic and validation
 */
public class SubscriptionService {
    
    public static String getSubscriptionTier(Id accountId) {
        List<Employer_Subscription__c> subs = [
            SELECT Subscription_Tier__c, Status__c
            FROM Employer_Subscription__c
            WHERE Account__c = :accountId
            AND Status__c IN ('Active', 'Trial')
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        return subs.isEmpty() ? 'Free' : subs[0].Subscription_Tier__c;
    }
    
    public static void validateFeatureAccess(Id accountId, String featureName) {
        String tier = getSubscriptionTier(accountId);
        
        // Get feature configuration
        List<Feature_Flag__mdt> features = [
            SELECT Free_Tier_Enabled__c, Free_Tier_Limit__c,
                   Professional_Tier_Enabled__c, Enterprise_Tier_Enabled__c
            FROM Feature_Flag__mdt
            WHERE DeveloperName = :featureName
            LIMIT 1
        ];
        
        if (features.isEmpty()) {
            return; // Feature not configured, allow access
        }
        
        Feature_Flag__mdt feature = features[0];
        Boolean hasAccess = false;
        
        if (tier == 'Free') {
            hasAccess = feature.Free_Tier_Enabled__c;
            if (hasAccess && feature.Free_Tier_Limit__c != null) {
                // Check usage limits
                Integer usage = getFeatureUsage(accountId, featureName);
                hasAccess = usage < feature.Free_Tier_Limit__c;
            }
        } else if (tier == 'Professional') {
            hasAccess = feature.Professional_Tier_Enabled__c;
        } else if (tier == 'Enterprise') {
            hasAccess = feature.Enterprise_Tier_Enabled__c;
        }
        
        if (!hasAccess) {
            throw new SubscriptionException('This feature requires an upgraded subscription. Please upgrade to Professional.');
        }
    }
    
    public static Integer getFeatureUsage(Id accountId, String featureName) {
        Date monthStart = Date.today().toStartOfMonth();
        
        if (featureName == 'Flint_Conversations') {
            return [SELECT COUNT() FROM Chat_Interaction__c 
                    WHERE Account__c = :accountId AND Started_At__c >= :monthStart];
        } else if (featureName == 'Profile_Unlock') {
            return [SELECT COUNT() FROM CampaignMember 
                    WHERE Campaign.Employer__c = :accountId 
                    AND Full_Profile_Unlocked__c = true 
                    AND Unlocked_Date__c >= :monthStart];
        }
        return 0;
    }
    
    public static void trackFeatureUsage(Id accountId, String featureName) {
        // Usage is tracked via the actual records (Chat_Interaction, CampaignMember)
        // This method can be expanded for custom tracking if needed
    }
    
    public class SubscriptionException extends Exception {}
}