/**
 * ═══════════════════════════════════════════════════════════════════════════
 * FILE 2: CampaignMemberHandler.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Handler class for CampaignMember trigger logic
 * 
 * TASK COVERED: US-045-BE-023
 * 
 * RESPONSIBILITIES:
 *   - Collect affected Campaign IDs
 *   - Filter for Talent Pool campaigns only
 *   - Trigger metrics recalculation
 * ═══════════════════════════════════════════════════════════════════════════
 */
    public with sharing class CampaignMemberHandler {
    
    /** Record Type for Talent Pool campaigns */
    private static final String TALENT_POOL_RT = 'Talent_Pool';
    
    /** Cache for talent pool campaign IDs to avoid repeated queries */
    private static Set<Id> talentPoolCampaignIds;
    
    // ═══════════════════════════════════════════════════════════════════════
    // TRIGGER HANDLERS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Handles after insert of campaign members.
     * Triggers metrics update for affected talent pools.
     */
    public static void handleAfterInsert(List<CampaignMember> newMembers) {
        Set<Id> campaignIds = extractCampaignIds(newMembers);
        updateTalentPoolMetrics(campaignIds);
    }
    
    /**
     * Handles after update of campaign members.
     * Only triggers update if status changed (affects pool metrics).
     */
    public static void handleAfterUpdate(
        List<CampaignMember> newMembers, 
        Map<Id, CampaignMember> oldMap
    ) {
        Set<Id> campaignIds = new Set<Id>();
        
        for (CampaignMember m : newMembers) {
            CampaignMember oldMember = oldMap.get(m.Id);
            
            // Only update metrics if status changed
            if (m.Status != oldMember.Status) {
                campaignIds.add(m.CampaignId);
            }
        }
        
        if (!campaignIds.isEmpty()) {
            updateTalentPoolMetrics(campaignIds);
        }

        createApplicationStatusNotifications(newMembers, oldMap);
    }
    
    /**
     * Handles after delete of campaign members.
     */
    public static void handleAfterDelete(List<CampaignMember> oldMembers) {
        Set<Id> campaignIds = extractCampaignIds(oldMembers);
        updateTalentPoolMetrics(campaignIds);
    }
    
    /**
     * Handles after undelete of campaign members.
     */
    public static void handleAfterUndelete(List<CampaignMember> restoredMembers) {
        Set<Id> campaignIds = extractCampaignIds(restoredMembers);
        updateTalentPoolMetrics(campaignIds);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // HELPER METHODS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Extracts Campaign IDs from a list of CampaignMembers.
     */
    private static Set<Id> extractCampaignIds(List<CampaignMember> members) {
        Set<Id> campaignIds = new Set<Id>();
        for (CampaignMember m : members) {
            campaignIds.add(m.CampaignId);
        }
        return campaignIds;
    }
    
    /**
     * Filters for Talent Pool campaigns and triggers metrics update.
     * Uses async processing to avoid blocking DML operations.
     */
    private static void updateTalentPoolMetrics(Set<Id> campaignIds) {
        if (campaignIds.isEmpty()) return;
        
        // Filter to only Talent Pool campaigns
        Set<Id> talentPoolIds = filterTalentPoolCampaigns(campaignIds);
        
        if (talentPoolIds.isEmpty()) return;
        
        // Use future method to avoid mixed DML and improve performance
        if (!System.isFuture() && !System.isBatch() && !Test.isRunningTest()) {
            updateMetricsAsync(talentPoolIds);
        } else {
            // Already in async context or test - update synchronously
            TalentPoolMetricsService.updateMetricsForCampaigns(talentPoolIds);
        }
    }
    
    /**
     * Filters campaign IDs to only include Talent Pool record type.
     */
    private static Set<Id> filterTalentPoolCampaigns(Set<Id> campaignIds) {
        Set<Id> talentPoolIds = new Set<Id>();
        
        // Check if RecordType exists
        Map<String, RecordTypeInfo> rtInfos = Schema.SObjectType.Campaign
            .getRecordTypeInfosByDeveloperName();
        
        if (!rtInfos.containsKey(TALENT_POOL_RT)) {
            // No Talent Pool record type - return all campaigns
            // (or return empty if you want strict filtering)
            return campaignIds;
        }
        
        Id talentPoolRTId = rtInfos.get(TALENT_POOL_RT).getRecordTypeId();
        
        for (Campaign c : [
            SELECT Id 
            FROM Campaign 
            WHERE Id IN :campaignIds 
            AND RecordTypeId = :talentPoolRTId
        ]) {
            talentPoolIds.add(c.Id);
        }
        
        return talentPoolIds;
    }
    
    /**
     * Async wrapper for metrics update.
     * Runs in separate transaction for better performance.
     */
    @future
    private static void updateMetricsAsync(Set<Id> campaignIds) {
        TalentPoolMetricsService.updateMetricsForCampaigns(campaignIds);
    }

    private static void createApplicationStatusNotifications(
        List<CampaignMember> newMembers,
        Map<Id, CampaignMember> oldMap
    ) {
        Set<Id> changedMemberIds = new Set<Id>();

        for (CampaignMember member : newMembers) {
            CampaignMember oldMember = oldMap.get(member.Id);
            if (oldMember != null && member.Status != oldMember.Status && member.Status != 'Interview_Requested') {
                changedMemberIds.add(member.Id);
            }
        }

        if (changedMemberIds.isEmpty()) return;

        List<NotificationService.NotificationRequest> requests = new List<NotificationService.NotificationRequest>();
        for (CampaignMember member : [
            SELECT Id, ContactId, Status, Campaign.Name
            FROM CampaignMember
            WHERE Id IN :changedMemberIds
        ]) {
            NotificationService.NotificationRequest request = new NotificationService.NotificationRequest();
            request.recipientId = member.ContactId;
            request.notificationType = 'Application';
            request.title = 'Application status update';
            request.description = member.Campaign.Name + ' changed to ' + member.Status + '.';
            request.linkTo = '/dashboard';
            request.priority = 'Normal';
            requests.add(request);
        }

        NotificationService.notifyMany(requests);
    }
}