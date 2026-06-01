/**
 * ═══════════════════════════════════════════════════════════════════════════
 * FILE 1: TalentPoolMetricsBatch.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Daily batch job to recalculate all talent pool metrics
 * 
 * TASKS COVERED:
 *   - US-045-BE-024: Create TalentPoolMetricsBatch.cls
 * 
 * FEATURES:
 *   - Processes all active Talent Pool campaigns
 *   - Recalculates all metrics (size, freshness, quality)
 *   - Marks expired members based on Intent_Expiry_Date__c
 *   - Sends summary email on completion
 * 
 * SCHEDULING: Run daily at 2 AM (configured in TalentPoolMetricsScheduler)
 * ═══════════════════════════════════════════════════════════════════════════
 */
public class TalentPoolMetricsBatch implements Database.Batchable<SObject>, Database.Stateful {
    
    // ═══════════════════════════════════════════════════════════════════════
    // STATEFUL VARIABLES (persist across batch chunks)
    // ═══════════════════════════════════════════════════════════════════════
    
    /** Count of campaigns processed */
    private Integer campaignsProcessed = 0;
    
    /** Count of members marked as expired */
    private Integer membersExpired = 0;
    
    /** Count of errors encountered */
    private Integer errorCount = 0;
    
    /** Error messages for logging */
    private List<String> errorMessages = new List<String>();
    
    /** Start time for duration tracking */
    private DateTime startTime;
    
    /** Record Type for Talent Pool campaigns */
    private static final String TALENT_POOL_RT = 'Talent_Pool';
    
    // ═══════════════════════════════════════════════════════════════════════
    // BATCH START
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Returns query locator for all active Talent Pool campaigns.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        startTime = DateTime.now();
        
        String query = 'SELECT Id, Name, Employer__c ' +
                       'FROM Campaign ' +
                       'WHERE IsActive = true';
        
        // Add Record Type filter if it exists
        Map<String, RecordTypeInfo> rtInfos = Schema.SObjectType.Campaign
            .getRecordTypeInfosByDeveloperName();
        
        if (rtInfos.containsKey(TALENT_POOL_RT)) {
            Id rtId = rtInfos.get(TALENT_POOL_RT).getRecordTypeId();
            query += ' AND RecordTypeId = \'' + rtId + '\'';
        } else {
            // Fallback: Filter by Type field
            query += ' AND Type = \'Employer Interest Pool\'';
        }
        
        return Database.getQueryLocator(query);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // BATCH EXECUTE
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Processes a batch of campaigns:
     * 1. Marks expired members
     * 2. Recalculates all metrics
     */
    public void execute(Database.BatchableContext bc, List<Campaign> campaigns) {
        Set<Id> campaignIds = new Set<Id>();
        for (Campaign c : campaigns) {
            campaignIds.add(c.Id);
        }
        
        try {
            // Step 1: Mark expired members
            Integer expired = markExpiredMembers(campaignIds);
            membersExpired += expired;
            
            // Step 2: Recalculate metrics
            TalentPoolMetricsService.updateMetricsForCampaigns(campaignIds);
            
            campaignsProcessed += campaigns.size();
            
        } catch (Exception e) {
            errorCount++;
            errorMessages.add('Batch error: ' + e.getMessage() + 
                            ' | Stack: ' + e.getStackTraceString());
        }
    }
    
    /**
     * Marks CampaignMembers as 'Expired' if their intent has expired.
     * Uses Intent_Expiry_Date__c formula field (Intent_Added_Date__c + 365)
     * 
     * @param campaignIds Set of Campaign IDs to process
     * @return Count of members marked as expired
     */
    private Integer markExpiredMembers(Set<Id> campaignIds) {
        Date today = Date.today();
        
        // Query members that should be expired
        // Intent_Expiry_Date__c is a formula: Intent_Added_Date__c + 365
        List<CampaignMember> membersToExpire = [
            SELECT Id, Status
            FROM CampaignMember
            WHERE CampaignId IN :campaignIds
            AND Status NOT IN ('Expired', 'Opted_Out')
            AND Intent_Expiry_Date__c < :today
        ];
        
        if (membersToExpire.isEmpty()) {
            return 0;
        }
        
        // Update status to Expired
        for (CampaignMember m : membersToExpire) {
            m.Status = 'Expired';
        }
        
        update membersToExpire;
        
        return membersToExpire.size();
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // BATCH FINISH
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Sends summary email and logs results.
     */
    public void finish(Database.BatchableContext bc) {
        DateTime endTime = DateTime.now();
        Long durationMs = endTime.getTime() - startTime.getTime();
        String duration = formatDuration(durationMs);
        
        // Build summary message
        String summary = buildSummaryMessage(duration);
        
        // Log to debug
        System.debug(LoggingLevel.INFO, summary);
        
        // Send email notification if configured
        sendNotificationEmail(summary);
    }
    
    /**
     * Builds a summary message of batch execution.
     */
    private String buildSummaryMessage(String duration) {
        String summary = '\n═══════════════════════════════════════════════════════\n' +
                        'TALENT POOL METRICS BATCH - COMPLETION SUMMARY\n' +
                        '═══════════════════════════════════════════════════════\n' +
                        'Completed At: ' + DateTime.now().format() + '\n' +
                        'Duration: ' + duration + '\n' +
                        'Campaigns Processed: ' + campaignsProcessed + '\n' +
                        'Members Expired: ' + membersExpired + '\n' +
                        'Errors: ' + errorCount + '\n';
        
        if (!errorMessages.isEmpty()) {
            summary += '\nERROR DETAILS:\n';
            for (String err : errorMessages) {
                summary += '  • ' + err + '\n';
            }
        }
        
        summary += '═══════════════════════════════════════════════════════\n';
        
        return summary;
    }
    
    /**
     * Sends notification email to admins.
     */
    private void sendNotificationEmail(String summary) {
        // Get admin email from custom setting or use default
        String adminEmail = getAdminEmail();
        
        if (String.isBlank(adminEmail)) return;
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{adminEmail});
        email.setSubject('Talent Pool Metrics Batch Complete - ' + Date.today().format());
        email.setPlainTextBody(summary);
        
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{email});
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to send notification email: ' + e.getMessage());
        }
    }
    
    /**
     * Gets admin email from org settings.
     * Override this method or use Custom Metadata for configuration.
     */
    private String getAdminEmail() {
        // Option 1: From Custom Setting
        // return Talent_Pool_Settings__c.getInstance().Admin_Email__c;
        
        // Option 2: From running user (for testing)
        // return UserInfo.getUserEmail();
        
        // Option 3: Return null to skip email
        return null;
    }
    
    /**
     * Formats milliseconds into human-readable duration.
     */
    private String formatDuration(Long milliseconds) {
        Long seconds = milliseconds / 1000;
        Long minutes = seconds / 60;
        Long remainingSeconds = Math.mod(seconds, 60);
        
        if (minutes > 0) {
            return minutes + ' min ' + remainingSeconds + ' sec';
        }
        return seconds + ' sec';
    }
}