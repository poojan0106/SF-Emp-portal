/**
 * ═══════════════════════════════════════════════════════════════════════════
 * TalentPoolService.cls (UPDATED)
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Manages talent pool creation and membership
 * 
 * UPDATES:
 *   - US-045-BE-030: Added dual membership (main pool + sub-pool)
 *   - Integration with TalentPoolSegmentationService
 * 
 * FLOW:
 *   1. Right swipe → Create/find main Campaign
 *   2. Add to main pool as CampaignMember
 *   3. Determine segment based on candidate profile
 *   4. Create/find sub-pool Campaign (child of main)
 *   5. Add to sub-pool as CampaignMember
 * ═══════════════════════════════════════════════════════════════════════════
 */
public with sharing class TalentPoolService {
    
    private static final String TALENT_POOL_RT = 'Talent_Pool';
    
    //Test 
    
    /** All status values used by the talent pool system */
    public static final List<StatusConfig> TALENT_POOL_STATUSES = new List<StatusConfig>{
            // Initial Interest Stage
        new StatusConfig('Interested', true, true, 10),           // Swipe Right (Default)
        
            new StatusConfig('In League', true, true, 20),
        
        // Employer Engagement Stage
        new StatusConfig('Viewed', true, false, 30),              // Employer Viewed
        new StatusConfig('Unlocked', true, false, 40),            // Profile Revealed
        
        // Interview Stage
        new StatusConfig('Interview_Requested', true, false, 50), // Interview Requested
        new StatusConfig('Interview_Scheduled', true, false, 60), // Interview Scheduled
        new StatusConfig('Interviewed', true, false, 70),         // Interviewed
        
        // Outcome Stage
        new StatusConfig('Offered', true, false, 80),             // Offer Made
        new StatusConfig('Placed', true, false, 90),              // Successfully Placed
        
        // Negative Outcomes
        new StatusConfig('Rejected', false, false, 100),           // Rejected by Employer
        new StatusConfig('Withdrawn', false, false, 110),         // Candidate Withdrew
        
        // System Statuses (existing)
        new StatusConfig('Expired', false, false, 120),           // Auto-expired after 12 months
        new StatusConfig('Opted_Out', false, false, 130)
    };
    
    /**
     * Adds candidates to employer talent pools based on right swipes.
     * 
     * UPDATED: Now also adds to segmented sub-pools.
     * 
     * @param rightSwipes List of right-direction swipe events
     */
    public static void addCandidatesToPools(List<Swipe_Event__c> rightSwipes) {
        
        System.debug('addCandidatesToPools START');
        
        if (rightSwipes == null || rightSwipes.isEmpty()) return;
        
        // Step 1: Get unique employer IDs
        Set<Id> employerIds = new Set<Id>();
        for (Swipe_Event__c swipe : rightSwipes) {
            employerIds.add(swipe.Employers__c);
        }
        System.debug('Unique employers=' + employerIds);
        
        // Step 2: Find existing talent pool campaigns
        Map<Id, Campaign> existingPools = getExistingTalentPools(employerIds);
        System.debug('Existing pools found=' + existingPools.size());
        
        // Step 3: Create campaigns for employers without pools
        Map<Id, Account> employers = new Map<Id, Account>([
            SELECT Id, Name FROM Account WHERE Id IN :employerIds
        ]);
        
        List<Campaign> newCampaigns = new List<Campaign>();
        Id talentPoolRTId = getTalentPoolRecordTypeId();
        
        for (Id empId : employerIds) {
            if (!existingPools.containsKey(empId)) {
                System.debug('Creating new pool for employer=' + empId);
                Campaign pool = new Campaign(
                    Name = employers.get(empId).Name + ' - Talent Pool',
                    Type = 'Employer Interest Pool',
                    Pool_Type__c = 'Employer_Interest',  // Main pool type
                    Status = 'In League',
                    IsActive = true,
                    Entry_Timestamp__c = System.now(),
                    Employer__c = empId
                );
                
                if (talentPoolRTId != null) {
                    pool.RecordTypeId = talentPoolRTId;
                }
                
                newCampaigns.add(pool);
            }
        }
        
        if (!newCampaigns.isEmpty()) {
            insert newCampaigns;
            System.debug('Inserted new campaigns=' + newCampaigns.size());
            List<Id> newCampaignIds = new List<Id>();
            for (Campaign c : newCampaigns) {
                existingPools.put(c.Employer__c, c);
                newCampaignIds.add(c.Id);
                System.debug('New campaign ID: ' + c.Id + ' for employer: ' + c.Employer__c);
            }
            
            // Create required statuses for new campaigns
	            createTalentPoolStatuses(newCampaignIds);
            System.debug('createTalentPoolStatuses completed');
        }
        
        // Step 4: Create campaign members for MAIN pool
        List<CampaignMember> mainPoolMembers = new List<CampaignMember>();
        Map<Id, Id> candidateToParentCampaign = new Map<Id, Id>();
        Map<Id, Id> candidateToSwipeEvent = new Map<Id, Id>();
        
        for (Swipe_Event__c swipe : rightSwipes) {
            Campaign pool = existingPools.get(swipe.Employers__c);
            
            if (pool != null) {
                CampaignMember member = new CampaignMember(
                    CampaignId = pool.Id,
                    ContactId = swipe.Candidate__c,
                    Status = 'Interested',
                    Intent_Added_Date__c = Date.today(),
                    Intent_Source__c = 'Swipe',
                    Swipe_Event__c = swipe.Id  
                );
                mainPoolMembers.add(member);
                
                // Track for sub-pool creation
                candidateToParentCampaign.put(swipe.Candidate__c, pool.Id);
                candidateToSwipeEvent.put(swipe.Candidate__c, swipe.Id);
            }
        }
        
        System.debug('Main pool members to insert=' + mainPoolMembers.size());
        // Insert main pool members (with partial success for duplicates)
        if (!mainPoolMembers.isEmpty()) {
            Database.SaveResult[] mainResults = Database.insert(mainPoolMembers, false);
            
            // Log any errors (but continue processing)
            for (Integer i = 0; i < mainResults.size(); i++) {
                if (!mainResults[i].isSuccess()) {
                    for (Database.Error err : mainResults[i].getErrors()) {
                        System.debug(LoggingLevel.WARN, 
                            'Main pool member insert error: ' + err.getMessage());
                    }
                }
            }
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // TASK US-045-BE-030: DUAL MEMBERSHIP - Add to Sub-Pools
        // ═══════════════════════════════════════════════════════════════════
        
        // Build membership info for bulk segmentation
        List<TalentPoolSegmentationService.MembershipInfo> membershipData = 
            new List<TalentPoolSegmentationService.MembershipInfo>();
        
        for (Id candidateId : candidateToParentCampaign.keySet()) {
            membershipData.add(new TalentPoolSegmentationService.MembershipInfo(
                candidateId,
                candidateToParentCampaign.get(candidateId),
                candidateToSwipeEvent.get(candidateId)
            ));
        }
        
        // Add to segmented sub-pools
        if (!membershipData.isEmpty()) {
            System.debug('Calling segmentation service...');
            TalentPoolSegmentationService.addToSegmentedPoolsBulk(membershipData);
            System.debug('Segmentation service completed.');
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // NEW: STATUS CREATION METHODS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Creates all required CampaignMemberStatus values for talent pool campaigns.
     * 
     * @param campaignIds List of Campaign IDs to create statuses for
     */
    /**
 * Creates all required CampaignMemberStatus values for talent pool campaigns.
 * Handles duplicates gracefully.
 * 
 * @param campaignIds List of Campaign IDs to create statuses for
 */
public static void createTalentPoolStatuses(List<Id> campaignIds) {
    if (campaignIds == null || campaignIds.isEmpty()) return;
    
    System.debug('createTalentPoolStatuses START for ' + campaignIds.size() + ' campaigns');
    
    // Step 1: Query existing statuses
    Map<Id, Set<String>> existingLabelsByCampaign = new Map<Id, Set<String>>();
    
    for (CampaignMemberStatus cms : [
        SELECT Id, CampaignId, Label, IsDefault
        FROM CampaignMemberStatus 
        WHERE CampaignId IN :campaignIds
    ]) {
        if (!existingLabelsByCampaign.containsKey(cms.CampaignId)) {
            existingLabelsByCampaign.put(cms.CampaignId, new Set<String>());
        }
        existingLabelsByCampaign.get(cms.CampaignId).add(cms.Label.toUpperCase().trim());
        System.debug('Found existing: "' + cms.Label + '" for campaign ' + cms.CampaignId);
    }
    
    // Step 2: Build list of statuses to create
    List<CampaignMemberStatus> statusesToInsert = new List<CampaignMemberStatus>();
    Map<Id, CampaignMemberStatus> interestedStatusByCampaign = new Map<Id, CampaignMemberStatus>();
    
    for (Id campaignId : campaignIds) {
        Set<String> existingLabels = existingLabelsByCampaign.get(campaignId);
        if (existingLabels == null) {
            existingLabels = new Set<String>();
        }
        
        for (StatusConfig config : TALENT_POOL_STATUSES) {
            String labelUppercase = config.label.toUpperCase().trim();
            
            if (!existingLabels.contains(labelUppercase)) {
                CampaignMemberStatus newStatus = new CampaignMemberStatus(
                    CampaignId = campaignId,
                    Label = config.label,
                    HasResponded = config.hasResponded,
                    IsDefault = false,
                    SortOrder = config.sortOrder
                );
                statusesToInsert.add(newStatus);
                
                if (config.label == 'Interested') {
                    interestedStatusByCampaign.put(campaignId, newStatus);
                }
                
                System.debug('Will create: "' + config.label + '" for campaign ' + campaignId);
            }
        }
    }
    
    // Step 3: Insert statuses ONE BY ONE to identify exact failures
    if (!statusesToInsert.isEmpty()) {
        System.debug('Inserting ' + statusesToInsert.size() + ' statuses individually...');
        
        Integer successCount = 0;
        
        for (CampaignMemberStatus newStatus : statusesToInsert) {
            try {
                insert newStatus;
                successCount++;
                System.debug('✓ Created: "' + newStatus.Label + '" (ID: ' + newStatus.Id + ')');
            } catch (DmlException e) {
                System.debug(LoggingLevel.ERROR, '✗ FAILED: "' + newStatus.Label + '"');
                System.debug(LoggingLevel.ERROR, '  Error: ' + e.getDmlStatusCode(0) + ' - ' + e.getDmlMessage(0));
            }
        }
        
        System.debug('Created ' + successCount + ' of ' + statusesToInsert.size() + ' statuses');
    }
    
    // Step 4: Set 'Interested' as default
    List<CampaignMemberStatus> statusesToMakeDefault = new List<CampaignMemberStatus>();
    
    for (Id campaignId : campaignIds) {
        CampaignMemberStatus interestedStatus = interestedStatusByCampaign.get(campaignId);
        
        if (interestedStatus != null && interestedStatus.Id != null) {
            statusesToMakeDefault.add(new CampaignMemberStatus(
                Id = interestedStatus.Id,
                IsDefault = true
            ));
        } else {
            // Query for existing 'Interested' status
            List<CampaignMemberStatus> existing = [
                SELECT Id, IsDefault FROM CampaignMemberStatus 
                WHERE CampaignId = :campaignId AND Label = 'Interested'
                LIMIT 1
            ];
            if (!existing.isEmpty() && !existing[0].IsDefault) {
                statusesToMakeDefault.add(new CampaignMemberStatus(
                    Id = existing[0].Id,
                    IsDefault = true
                ));
            }
        }
    }
    
    if (!statusesToMakeDefault.isEmpty()) {
        try {
            update statusesToMakeDefault;
            System.debug('✓ Set "Interested" as default for ' + statusesToMakeDefault.size() + ' campaigns');
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, '✗ Error setting default: ' + e.getMessage());
        }
    }
    
    System.debug('createTalentPoolStatuses COMPLETE');
}
    
    /**
     * Ensures statuses exist for existing campaigns (for data migration).
     * Call this for campaigns that were created before this fix.
     * 
     * @param employerIds Set of employer Account IDs
     */
    public static void ensureStatusesForExistingPools(Set<Id> employerIds) {
        Map<Id, Campaign> pools = getExistingTalentPools(employerIds);
        
        if (!pools.isEmpty()) {
            List<Id> campaignIds = new List<Id>();
            for (Campaign c : pools.values()) {
                campaignIds.add(c.Id);
            }
            createTalentPoolStatuses(campaignIds);
        }
    }
    
    /**
     * Removes a candidate from an employer's talent pool AND sub-pools.
     * Called when a swipe is undone.
     * 
     * @param candidateId Contact Id
     * @param employerId Account Id
     */
    public static void removeCandidateFromPool(Id candidateId, Id employerId) {
         System.debug('removeCandidateFromPool START');
        Campaign pool = getTalentPoolForEmployer(employerId);
        
        if (pool == null) return;
        
        // Get all pools (parent + children) for this employer
        Set<Id> allPoolIds = new Set<Id>{pool.Id};
        
        // Get sub-pools (children)
        for (Campaign subPool : [
            SELECT Id FROM Campaign WHERE ParentId = :pool.Id
        ]) {
            allPoolIds.add(subPool.Id);
        }
        
        // Delete all memberships
        List<CampaignMember> members = [
            SELECT Id 
            FROM CampaignMember 
            WHERE CampaignId IN :allPoolIds 
            AND ContactId = :candidateId
        ];
        
        if (!members.isEmpty()) {
            delete members;
        }
        System.debug('removeCandidateFromPool END');
    }
    
    /**
     * Gets existing talent pool campaigns for given employers.
     * Only returns PARENT pools (ParentId = null).
     */
    private static Map<Id, Campaign> getExistingTalentPools(Set<Id> employerIds) {
        System.debug('getExistingTalentPools for employers=' + employerIds);
        Map<Id, Campaign> poolMap = new Map<Id, Campaign>();
        
        String query = 'SELECT Id, Employer__c, Name, RecordTypeId FROM Campaign ' +
                       'WHERE Employer__c IN :employerIds ' +
                       'AND IsActive = true ' +
                       'AND ParentId = null';  // Only parent pools
        
        Map<String, RecordTypeInfo> rtInfos = Schema.SObjectType.Campaign
            .getRecordTypeInfosByDeveloperName();
        
        if (rtInfos.containsKey(TALENT_POOL_RT)) {
            query += ' AND RecordType.DeveloperName = :TALENT_POOL_RT';
        }
        
        for (Campaign c : Database.query(query)) {
            poolMap.put(c.Employer__c, c);
        }
        
        return poolMap;
    }
    
    /**
     * Gets the talent pool campaign for a single employer.
     */
    private static Campaign getTalentPoolForEmployer(Id employerId) {
        Set<Id> employerIds = new Set<Id>{employerId};
        Map<Id, Campaign> pools = getExistingTalentPools(employerIds);
        return pools.get(employerId);
    }
    
    /**
     * Gets Talent Pool Record Type Id.
     */
    private static Id getTalentPoolRecordTypeId() {
        Map<String, RecordTypeInfo> rtInfos = Schema.SObjectType.Campaign
            .getRecordTypeInfosByDeveloperName();
        
        if (rtInfos.containsKey(TALENT_POOL_RT)) {
            System.debug('Talent pool RT');
            return rtInfos.get(TALENT_POOL_RT).getRecordTypeId();
        }
        return null;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // INNER CLASS: Status Configuration
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Configuration for a CampaignMemberStatus value.
     */
    public class StatusConfig {
        public String label;
        public Boolean hasResponded;
        public Boolean isDefault;
        public Integer sortOrder;
        
        public StatusConfig(String label, Boolean hasResponded, Boolean isDefault, Integer sortOrder) {
            this.label = label;
            this.hasResponded = hasResponded;
            this.isDefault = isDefault;
            this.sortOrder = sortOrder;
        }
    }
}