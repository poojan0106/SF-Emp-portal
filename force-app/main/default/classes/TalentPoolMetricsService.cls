/**
 * ═══════════════════════════════════════════════════════════════════════════
 * TalentPoolMetricsService.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Service class for calculating and updating talent pool metrics
 * 
 * TASKS COVERED:
 *   - US-045-BE-018: Create TalentPoolMetricsService.cls
 *   - US-045-BE-019: Build calculatePoolSize() method
 *   - US-045-BE-020: Build calculateNewMembersThisWeek() method
 *   - US-045-BE-021: Build calculateAverageIntentCurrency() method
 *   - US-045-BE-022: Build calculateQualityScore() method
 * 
 * METRICS CALCULATED:
 *   - Pool_Size__c: Count of active (non-expired, non-opted-out) members
 *   - New_Members_This_Week__c: Members added in last 7 days
 *   - Average_Intent_Currency__c: Avg days since members joined
 *   - Quality_Score__c: Composite score (0-100) based on freshness + completeness
 *   - Active_Members_Count__c: Members with recent activity
 * 
 * AUTHOR: [Your Name]
 * DATE: January 2025
 * ═══════════════════════════════════════════════════════════════════════════
 */
public with sharing class TalentPoolMetricsService {
    
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════
    
    /** Statuses considered "active" for pool membership */
    private static final Set<String> ACTIVE_STATUSES = new Set<String>{
        'Interested', 'Engaged', 'Contacted', 'Interviewed'
    };
    
    /** Statuses excluded from active count */
    private static final Set<String> INACTIVE_STATUSES = new Set<String>{
        'Expired', 'Opted_Out'
    };
    
    /** Days to consider a member "recently active" */
    private static final Integer ACTIVE_THRESHOLD_DAYS = 30;
    
    /** Days for intent to be considered "fresh" (full quality score) */
    private static final Integer FRESH_INTENT_DAYS = 30;
    
    /** Days after which intent quality degrades significantly */
    private static final Integer STALE_INTENT_DAYS = 180;
    
    /** Weight for intent freshness in quality score (0-1) */
    private static final Decimal FRESHNESS_WEIGHT = 0.6;
    
    /** Weight for profile completeness in quality score (0-1) */
    private static final Decimal COMPLETENESS_WEIGHT = 0.4;
    
    // ═══════════════════════════════════════════════════════════════════════
    // MAIN PUBLIC METHODS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Updates all metrics for specified campaigns.
     * Main entry point for trigger and batch processing.
     * 
     * @param campaignIds Set of Campaign IDs to update
     */
    public static void updateMetricsForCampaigns(Set<Id> campaignIds) {
        if (campaignIds == null || campaignIds.isEmpty()) return;
        
        // Get all metrics in one query for efficiency
        Map<Id, PoolMetrics> metricsMap = calculateAllMetrics(campaignIds);
        
        // Build campaign updates
        List<Campaign> campaignsToUpdate = new List<Campaign>();
        
        for (Id campId : campaignIds) {
            PoolMetrics metrics = metricsMap.get(campId);
            if (metrics == null) {
                metrics = new PoolMetrics(); // Empty metrics for campaigns with no members
            }
            
            Campaign camp = new Campaign(
                Id = campId,
                Pool_Size__c = metrics.poolSize,
                New_Members_This_Week__c = metrics.newMembersThisWeek,
                Average_Intent_Currency__c = metrics.avgIntentCurrency,
                Quality_Score__c = metrics.qualityScore,
                Active_Members_Count__c = metrics.activeMembersCount
            );
            campaignsToUpdate.add(camp);
        }
        
        if (!campaignsToUpdate.isEmpty()) {
            update campaignsToUpdate;
        }
    }
    
    /**
     * Updates metrics for a single campaign.
     * Convenience method for single-record operations.
     * 
     * @param campaignId Campaign ID to update
     */
    public static void updateMetricsForCampaign(Id campaignId) {
        updateMetricsForCampaigns(new Set<Id>{campaignId});
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TASK US-045-BE-019: calculatePoolSize()
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Counts active (non-expired, non-opted-out) Campaign Members.
     * 
     * @param campaignId Campaign ID
     * @return Count of active members
     */
    public static Integer calculatePoolSize(Id campaignId) {
        return [
            SELECT COUNT()
            FROM CampaignMember
            WHERE CampaignId = :campaignId
            AND Status IN :ACTIVE_STATUSES
        ];
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TASK US-045-BE-020: calculateNewMembersThisWeek()
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Counts members added in the last 7 days.
     * Uses Intent_Added_Date__c if available, falls back to CreatedDate.
     * 
     * @param campaignId Campaign ID
     * @return Count of new members this week
     */
    public static Integer calculateNewMembersThisWeek(Id campaignId) {
        Date sevenDaysAgo = Date.today().addDays(-7);
        
        return [
            SELECT COUNT()
            FROM CampaignMember
            WHERE CampaignId = :campaignId
            AND (
                Intent_Added_Date__c >= :sevenDaysAgo
                OR (Intent_Added_Date__c = null AND CreatedDate >= :sevenDaysAgo)
            )
        ];
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TASK US-045-BE-021: calculateAverageIntentCurrency()
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Calculates average days since members joined (intent currency).
     * Lower number = fresher intent = better.
     * 
     * Formula: AVG(TODAY - Intent_Added_Date__c) for all active members
     * 
     * @param campaignId Campaign ID
     * @return Average days since members joined (null if no members)
     */
    public static Decimal calculateAverageIntentCurrency(Id campaignId) {
        List<CampaignMember> members = [
            SELECT Intent_Added_Date__c, CreatedDate
            FROM CampaignMember
            WHERE CampaignId = :campaignId
            AND Status IN :ACTIVE_STATUSES
        ];
        
        System.debug('Members found: ' + members.size());
        
        if (members.isEmpty()) return null;
        
        Decimal totalDays = 0;
        Integer count = 0;
        Date today = Date.today();
        
        for (CampaignMember m : members) {
            Date addedDate = m.Intent_Added_Date__c != null 
                           ? m.Intent_Added_Date__c 
                           : m.CreatedDate.date();
            
            Integer daysSince = addedDate.daysBetween(today);
            System.debug('Member processed → Added Date: ' + addedDate +
                     ', Days Since: ' + daysSince);
            totalDays += daysSince;
            count++;
        }
        
        System.debug('Total Days: ' + totalDays);
    	System.debug('Count: ' + count);
        
        Decimal result = count > 0 ? (totalDays / count).setScale(1) : null;

    	System.debug('Final Average: ' + result);
        
        return count > 0 ? (totalDays / count).setScale(1) : null;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TASK US-045-BE-022: calculateQualityScore()
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Calculates quality score (0-100) based on:
     *   - Intent Freshness (60% weight): How recent are the swipes
     *   - Profile Completeness (40% weight): How complete are member profiles
     * 
     * FRESHNESS SCORING:
     *   - 0-30 days: 100 points
     *   - 31-180 days: Linear decay from 100 to 50
     *   - 181-365 days: Linear decay from 50 to 0
     *   - 365+ days: 0 points
     * 
     * @param campaignId Campaign ID
     * @return Quality score 0-100 (null if no members)
     */
    public static Decimal calculateQualityScore(Id campaignId) {
        // Query members with their contact's profile completeness
        List<CampaignMember> members = [
            SELECT Intent_Added_Date__c, CreatedDate,
                   Contact.Profile_Completeness__c
            FROM CampaignMember
            WHERE CampaignId = :campaignId
            AND Status IN :ACTIVE_STATUSES
        ];
        
        if (members.isEmpty()) return null;
        
        Decimal totalFreshnessScore = 0;
        Decimal totalCompletenessScore = 0;
        Integer count = 0;
        Date today = Date.today();
        
        for (CampaignMember m : members) {
            // Calculate freshness score for this member
            Date addedDate = m.Intent_Added_Date__c != null 
                           ? m.Intent_Added_Date__c 
                           : m.CreatedDate.date();
            Integer daysSince = addedDate.daysBetween(today);
            Decimal freshnessScore = calculateFreshnessScore(daysSince);
            totalFreshnessScore += freshnessScore;
            
            // Get profile completeness (default to 50 if not set)
            Decimal completeness = m.Contact.Profile_Completeness__c != null 
                                  ? m.Contact.Profile_Completeness__c 
                                  : 50;
            totalCompletenessScore += completeness;
            
            count++;
        }
        
        if (count == 0) return null;
        
        // Calculate weighted average
        Decimal avgFreshness = totalFreshnessScore / count;
        Decimal avgCompleteness = totalCompletenessScore / count;
        
        Decimal qualityScore = (avgFreshness * FRESHNESS_WEIGHT) + 
                               (avgCompleteness * COMPLETENESS_WEIGHT);
        
        return qualityScore.setScale(0);
    }
    
    /**
     * Calculates freshness score based on days since intent.
     * 
     * @param daysSince Days since member joined
     * @return Freshness score 0-100
     */
    private static Decimal calculateFreshnessScore(Integer daysSince) {
        if (daysSince <= FRESH_INTENT_DAYS) {
            // Fresh: Full score
            return 100;
        } else if (daysSince <= STALE_INTENT_DAYS) {
            // Aging: Linear decay from 100 to 50
            Decimal range = STALE_INTENT_DAYS - FRESH_INTENT_DAYS;
            Decimal daysInRange = daysSince - FRESH_INTENT_DAYS;
            return 100 - ((daysInRange / range) * 50);
        } else if (daysSince <= 365) {
            // Stale: Linear decay from 50 to 0
            Decimal range = 365 - STALE_INTENT_DAYS;
            Decimal daysInRange = daysSince - STALE_INTENT_DAYS;
            return 50 - ((daysInRange / range) * 50);
        }
        // Expired
        return 0;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // BULK CALCULATION METHOD (for efficiency)
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Calculates all metrics for multiple campaigns in one operation.
     * More efficient than calling individual methods for batch processing.
     * 
     * @param campaignIds Set of Campaign IDs
     * @return Map of Campaign ID to PoolMetrics
     */
    public static Map<Id, PoolMetrics> calculateAllMetrics(Set<Id> campaignIds) {
        Map<Id, PoolMetrics> metricsMap = new Map<Id, PoolMetrics>();
        
        // Initialize metrics for all campaigns
        for (Id campId : campaignIds) {
            metricsMap.put(campId, new PoolMetrics());
        }
        
        Date today = Date.today();
        Date sevenDaysAgo = today.addDays(-7);
        Date thirtyDaysAgo = today.addDays(-ACTIVE_THRESHOLD_DAYS);
        
        // Query all members for all campaigns at once
        List<CampaignMember> allMembers = [
            SELECT CampaignId, Status, Intent_Added_Date__c, CreatedDate,
                   Contact.Profile_Completeness__c, Contact.Last_Activity_Date__c
            FROM CampaignMember
            WHERE CampaignId IN :campaignIds
        ];
        
        // Process each member
        for (CampaignMember m : allMembers) {
            PoolMetrics metrics = metricsMap.get(m.CampaignId);
            
            Date addedDate = m.Intent_Added_Date__c != null 
                           ? m.Intent_Added_Date__c 
                           : m.CreatedDate.date();
            Integer daysSince = addedDate.daysBetween(today);
            System.debug('Added Date: ' + addedDate +
                 ' | Days Since: ' + daysSince);
            
            // Pool Size: Count active statuses
            if (ACTIVE_STATUSES.contains(m.Status)) {
                metrics.poolSize++;
                
                // For active members, calculate quality metrics
                metrics.totalDaysSinceAdded += daysSince;
                metrics.totalFreshnessScore += calculateFreshnessScore(daysSince);
                
                Decimal completeness = m.Contact.Profile_Completeness__c != null 
                                      ? m.Contact.Profile_Completeness__c : 50;
                metrics.totalCompletenessScore += completeness;
                
                // Active Members: Recent activity
                if (m.Contact.Last_Activity_Date__c != null && 
                    m.Contact.Last_Activity_Date__c >= thirtyDaysAgo) {
                    metrics.activeMembersCount++;
                }
            }
            
            // New This Week: Check add date regardless of status
            if (addedDate >= sevenDaysAgo) {
                metrics.newMembersThisWeek++;
            }
        }
        
        // Finalize calculated fields
        for (PoolMetrics metrics : metricsMap.values()) {
            metrics.finalize();
        }
        
        return metricsMap;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // INNER CLASS: Metrics Data Structure
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Data structure to hold calculated metrics for a campaign.
     */
    public class PoolMetrics {
        public Integer poolSize = 0;
        public Integer newMembersThisWeek = 0;
        public Decimal avgIntentCurrency = 0;
        public Decimal qualityScore = 0;
        public Integer activeMembersCount = 0;
        
        // Working fields for calculation
        public Decimal totalDaysSinceAdded = 0;
        public Decimal totalFreshnessScore = 0;
        public Decimal totalCompletenessScore = 0;
        
        /**
         * Finalizes calculated fields after aggregation.
         */
        public void finalize() {
            System.debug('Pool Size: ' + poolSize);
            if (poolSize > 0) {
                
                System.debug('Total Days Since Added: ' + totalDaysSinceAdded);
                System.debug('Total Freshness Score: ' + totalFreshnessScore);
                System.debug('Total Completeness Score: ' + totalCompletenessScore);
                
                // Average Intent Currency
                avgIntentCurrency = (totalDaysSinceAdded / poolSize).setScale(1);
                System.debug('Avg Intent Currency: ' + avgIntentCurrency);
                
                // Quality Score (weighted average)
                Decimal avgFreshness = totalFreshnessScore / poolSize;
                Decimal avgCompleteness = totalCompletenessScore / poolSize;
                System.debug('Avg Freshness: ' + avgFreshness);
		        System.debug('Avg Completeness: ' + avgCompleteness);
                
                qualityScore = ((avgFreshness * FRESHNESS_WEIGHT) + 
                               (avgCompleteness * COMPLETENESS_WEIGHT)).setScale(0);
                System.debug('Quality Score: ' + qualityScore);
            }
        }
    }
}