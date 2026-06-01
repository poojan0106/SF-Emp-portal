/**
 * ═══════════════════════════════════════════════════════════════════════════
 * TalentPoolSegmentationBatch.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Batch job to assign existing pool members to appropriate sub-pools
 * 
 * TASK COVERED: US-045-BE-028
 * 
 * USE CASES:
 *   1. Initial migration: Segment existing pool members
 *   2. Re-segmentation: When candidate updates their profile/skills
 *   3. Periodic sync: Ensure all members are in correct sub-pools
 * 
 * PROCESS:
 *   1. Query all CampaignMembers in parent talent pools
 *   2. For each member, determine segment based on candidate profile
 *   3. Create sub-pool membership if not already exists
 * 
 * SCHEDULING:
 *   - Run weekly or on-demand
 *   - TalentPoolSegmentationScheduler.scheduleWeekly();
 * 
 * AUTHOR: [Your Name]
 * DATE: January 2025
 * ═══════════════════════════════════════════════════════════════════════════
 */
public class TalentPoolSegmentationBatch implements Database.Batchable<SObject>, Database.Stateful {
    
    // ═══════════════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════
    
    /** Optional: Limit to specific employer */
    private Id employerIdFilter;
    
    /** Optional: Limit to specific parent campaign */
    private Id parentCampaignIdFilter;
    
    /** Whether to re-segment existing sub-pool members */
    private Boolean reSegmentExisting = false;
    
    // ═══════════════════════════════════════════════════════════════════════
    // STATEFUL TRACKING
    // ═══════════════════════════════════════════════════════════════════════
    
    private Integer membersProcessed = 0;
    private Integer membersSegmented = 0;
    private Integer subPoolsCreated = 0;
    private Integer errorCount = 0;
    private List<String> errorMessages = new List<String>();
    private DateTime startTime;
    
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTORS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Default constructor: Process all talent pools
     */
    public TalentPoolSegmentationBatch() {
        // Process all
    }
    
    /**
     * Constructor with employer filter
     */
    public TalentPoolSegmentationBatch(Id employerId) {
        this.employerIdFilter = employerId;
    }
    
    /**
     * Constructor with specific campaign filter
     */
    public TalentPoolSegmentationBatch(Id parentCampaignId, Boolean reSegment) {
        this.parentCampaignIdFilter = parentCampaignId;
        this.reSegmentExisting = reSegment;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // BATCH START
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Returns query locator for CampaignMembers in parent talent pools.
     * Only queries members in PARENT pools (ParentId = null).
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        startTime = DateTime.now();
        
        String query = 
            'SELECT Id, CampaignId, ContactId, Contact.Title, Contact.Department, ' +
            'Contact.Skills__c, Contact.Industry_Experience__c, Status, ' +
            'Campaign.Employer__c, Campaign.Employer__r.Name, Campaign.RecordTypeId ' +
            'FROM CampaignMember ' +
            'WHERE Campaign.IsActive = true ' +
            'AND Campaign.ParentId = null ' +  // Only parent pools
            'AND Campaign.Type = \'Employer Interest Pool\' ' +
            'AND Status NOT IN (\'Expired\', \'Opted_Out\')';
        
        // Apply filters
        if (parentCampaignIdFilter != null) {
            query += ' AND CampaignId = :parentCampaignIdFilter';
        } else if (employerIdFilter != null) {
            query += ' AND Campaign.Employer__c = :employerIdFilter';
        }
        
        query += ' ORDER BY CampaignId';
        
        return Database.getQueryLocator(query);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // BATCH EXECUTE
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Processes a batch of CampaignMembers:
     * 1. Groups by parent campaign
     * 2. Determines segment for each member
     * 3. Creates sub-pool memberships
     */
    public void execute(Database.BatchableContext bc, List<CampaignMember> members) {
        try {
            // Group members by parent campaign
            Map<Id, List<CampaignMember>> membersByParent = new Map<Id, List<CampaignMember>>();
            Set<Id> contactIds = new Set<Id>();
            
            for (CampaignMember m : members) {
                if (!membersByParent.containsKey(m.CampaignId)) {
                    membersByParent.put(m.CampaignId, new List<CampaignMember>());
                }
                membersByParent.get(m.CampaignId).add(m);
                contactIds.add(m.ContactId);
            }
            
            // Query Career Intents for candidates (for better segmentation)
            Map<Id, Career_Intent__c> careerIntents = getCareerIntents(contactIds);
            
            // Process each parent campaign group
            for (Id parentCampaignId : membersByParent.keySet()) {
                processParentCampaign(
                    parentCampaignId, 
                    membersByParent.get(parentCampaignId),
                    careerIntents
                );
            }
            
            membersProcessed += members.size();
            
        } catch (Exception e) {
            errorCount++;
            errorMessages.add('Execute error: ' + e.getMessage());
        }
    }
    
    /**
     * Processes members for a single parent campaign.
     */
    private void processParentCampaign(
        Id parentCampaignId, 
        List<CampaignMember> members,
        Map<Id, Career_Intent__c> careerIntents
    ) {
        // Determine segments for all members
        Map<Id, Set<String>> memberSegments = new Map<Id, Set<String>>();
        Set<String> allNeededSegments = new Set<String>();
        
        for (CampaignMember m : members) {
            // Build candidate profile for segmentation using wrapper class
            TalentPoolSegmentationService.CandidateProfile profile = 
                new TalentPoolSegmentationService.CandidateProfile();
            profile.contactId = m.ContactId;
            profile.title = m.Contact.Title;
            profile.department = m.Contact.Department;
            profile.skills = m.Contact.R_ATS__Skills__c;
            profile.industryExperience = m.Contact.Industry_Experience__c;
            
            // Add career intent if available
            if (careerIntents.containsKey(m.ContactId)) {
                profile.withCareerIntent(careerIntents.get(m.ContactId));
            }
            
            Set<String> segments = TalentPoolSegmentationService.determineSegments(profile);
            
            if (segments.isEmpty()) {
                segments.add(TalentPoolSegmentationService.SEGMENT_OTHER);
            }
            
            memberSegments.put(m.ContactId, segments);
            allNeededSegments.addAll(segments);
        }
        
        // Get or create sub-pools
        Map<String, Campaign> subPools = TalentPoolSegmentationService.getOrCreateSubPools(
            parentCampaignId, 
            allNeededSegments
        );
        
        // Track newly created sub-pools
        for (Campaign subPool : subPools.values()) {
            if (subPool.Id != null && subPool.CreatedDate == Date.today()) {
                subPoolsCreated++;
            }
        }
        
        // Get existing sub-pool memberships
        Set<String> existingMemberKeys = getExistingSubPoolMemberKeys(
            subPools.values(), 
            memberSegments.keySet()
        );
        
        // Create new sub-pool memberships
        List<CampaignMember> newMembers = new List<CampaignMember>();
        
        for (CampaignMember m : members) {
            Set<String> segments = memberSegments.get(m.ContactId);
            
            for (String segment : segments) {
                Campaign subPool = subPools.get(segment);
                if (subPool == null) continue;
                
                String memberKey = subPool.Id + '_' + m.ContactId;
                
                if (!existingMemberKeys.contains(memberKey)) {
                    CampaignMember newMember = new CampaignMember(
                        CampaignId = subPool.Id,
                        ContactId = m.ContactId,
                        Status = m.Status,  // Copy status from parent
                        Intent_Added_Date__c = Date.today(),
                        Intent_Source__c = 'Batch Segmentation'
                    );
                    newMembers.add(newMember);
                    existingMemberKeys.add(memberKey);
                    membersSegmented++;
                }
            }
        }
        
        // Insert new memberships
        if (!newMembers.isEmpty()) {
            Database.SaveResult[] results = Database.insert(newMembers, false);
            
            for (Database.SaveResult sr : results) {
                if (!sr.isSuccess()) {
                    for (Database.Error err : sr.getErrors()) {
                        // Ignore duplicate errors
                        if (!err.getMessage().contains('DUPLICATE')) {
                            errorCount++;
                            errorMessages.add('Insert error: ' + err.getMessage());
                        }
                    }
                }
            }
        }
    }
    
    /**
     * Builds a CandidateContext wrapper from CampaignMember for segmentation.
     * Note: Cannot assign to child relationship fields directly in Apex,
     * so we use a wrapper class instead.
     */
    private CandidateContext buildCandidateContext(
        CampaignMember m, 
        Map<Id, Career_Intent__c> careerIntents
    ) {
        CandidateContext ctx = new CandidateContext();
        ctx.contactId = m.ContactId;
        ctx.title = m.Contact.Title;
        ctx.department = m.Contact.Department;
        ctx.skills = m.Contact.R_ATS__Skills__c;
        ctx.industryExperience = m.Contact.Industry_Experience__c;
        
        // Add career intent if available
        if (careerIntents.containsKey(m.ContactId)) {
            Career_Intent__c intent = careerIntents.get(m.ContactId);
            ctx.targetRole = intent.Target_Role__c;
            ctx.targetIndustry = intent.Short_Term_Industry__c;
        }
        
        return ctx;
    }
    
    /**
     * Wrapper class to hold candidate data for segmentation.
     * Used because child relationship fields (Career_Intents__r) are read-only.
     */
    public class CandidateContext {
        public Id contactId;
        public String title;
        public String department;
        public String skills;
        public String industryExperience;
        public String targetRole;
        public String targetIndustry;
    }
    
    /**
     * Queries Career Intents for candidates.
     */
    private Map<Id, Career_Intent__c> getCareerIntents(Set<Id> contactIds) {
        Map<Id, Career_Intent__c> intentMap = new Map<Id, Career_Intent__c>();
        
        for (Career_Intent__c intent : [
            SELECT Id, Candidate__c, Target_Role__c, Short_Term_Industry__c
            FROM Career_Intent__c
            WHERE Candidate__c IN :contactIds
            ORDER BY CreatedDate DESC
        ]) {
            // Only keep the most recent intent per candidate
            if (!intentMap.containsKey(intent.Candidate__c)) {
                intentMap.put(intent.Candidate__c, intent);
            }
        }
        
        return intentMap;
    }
    
    /**
     * Gets existing sub-pool membership keys.
     */
    private Set<String> getExistingSubPoolMemberKeys(
        List<Campaign> subPools, 
        Set<Id> contactIds
    ) {
        Set<String> keys = new Set<String>();
        Set<Id> subPoolIds = new Set<Id>();
        
        for (Campaign c : subPools) {
            subPoolIds.add(c.Id);
        }
        
        for (CampaignMember m : [
            SELECT CampaignId, ContactId 
            FROM CampaignMember 
            WHERE CampaignId IN :subPoolIds 
            AND ContactId IN :contactIds
        ]) {
            keys.add(m.CampaignId + '_' + m.ContactId);
        }
        
        return keys;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // BATCH FINISH
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Logs summary and sends notification.
     */
    public void finish(Database.BatchableContext bc) {
        DateTime endTime = DateTime.now();
        Long durationMs = endTime.getTime() - startTime.getTime();
        
        String summary = buildSummary(durationMs);
        System.debug(LoggingLevel.INFO, summary);
        
        // Optional: Send email notification
        // sendNotificationEmail(summary);
    }
    
    /**
     * Builds summary message.
     */
    private String buildSummary(Long durationMs) {
        Long seconds = durationMs / 1000;
        
        return '\n' +
            '═══════════════════════════════════════════════════════════════\n' +
            '  TALENT POOL SEGMENTATION BATCH - COMPLETE\n' +
            '═══════════════════════════════════════════════════════════════\n' +
            '  Duration: ' + seconds + ' seconds\n' +
            '  Members Processed: ' + membersProcessed + '\n' +
            '  Members Segmented: ' + membersSegmented + '\n' +
            '  Sub-Pools Created: ' + subPoolsCreated + '\n' +
            '  Errors: ' + errorCount + '\n' +
            (errorMessages.isEmpty() ? '' : '  Error Details: ' + String.join(errorMessages, '; ') + '\n') +
            '═══════════════════════════════════════════════════════════════\n';
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // STATIC HELPER METHODS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Runs the batch immediately.
     */
    public static Id runNow() {
        return Database.executeBatch(new TalentPoolSegmentationBatch(), 100);
    }
    
    /**
     * Runs for a specific employer.
     */
    public static Id runForEmployer(Id employerId) {
        return Database.executeBatch(new TalentPoolSegmentationBatch(employerId), 100);
    }
    
    /**
     * Runs for a specific campaign.
     */
    public static Id runForCampaign(Id campaignId) {
        return Database.executeBatch(new TalentPoolSegmentationBatch(campaignId, false), 100);
    }
}