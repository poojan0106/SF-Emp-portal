/**
 * ═══════════════════════════════════════════════════════════════════════════
 * TalentPoolExpiryScheduler.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Schedulable wrapper for TalentPoolExpiryBatch
 * 
 * TASK COVERED: US-045-BE-037
 * 
 * SCHEDULING: Daily at 3 AM
 * 
 * USAGE:
 *   // Schedule via Anonymous Apex:
 *   TalentPoolExpiryScheduler.scheduleDaily();
 * ═══════════════════════════════════════════════════════════════════════════
 */
public class TalentPoolExpiryScheduler implements Schedulable {
    
    /** Job name for identification */
    public static final String JOB_NAME = 'Talent Pool Expiry - Daily 3AM';
    
    /** Cron expression: 3:00 AM every day */
    public static final String CRON_DAILY_3AM = '0 0 3 * * ?';
    
    /** Batch size for processing */
    private static final Integer BATCH_SIZE = 50;
    
    /**
     * Executes the scheduled job.
     */
    public void execute(SchedulableContext sc) {
        TalentPoolExpiryBatch batch = new TalentPoolExpiryBatch();
        Database.executeBatch(batch, BATCH_SIZE);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // SCHEDULING HELPER METHODS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Schedules the batch to run daily at 3 AM.
     * 
     * @return The scheduled job ID
     */
    public static String scheduleDaily() {
        abortExistingJob();
        return System.schedule(JOB_NAME, CRON_DAILY_3AM, new TalentPoolExpiryScheduler());
    }
    
    /**
     * Schedules with custom cron expression.
     * 
     * @param cronExpression Custom cron schedule
     * @return The scheduled job ID
     */
    public static String scheduleCustom(String cronExpression) {
        abortExistingJob();
        return System.schedule(JOB_NAME, cronExpression, new TalentPoolExpiryScheduler());
    }
    
    /**
     * Aborts any existing scheduled job with the same name.
     */
    public static void abortExistingJob() {
        List<CronTrigger> existingJobs = [
            SELECT Id 
            FROM CronTrigger 
            WHERE CronJobDetail.Name = :JOB_NAME
        ];
        
        for (CronTrigger ct : existingJobs) {
            System.abortJob(ct.Id);
        }
    }
    
    /**
     * Checks if the job is currently scheduled.
     */
    public static Boolean isScheduled() {
        return ![
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name = :JOB_NAME
            LIMIT 1
        ].isEmpty();
    }
    
    /**
     * Gets the next scheduled run time.
     */
    public static DateTime getNextRunTime() {
        List<CronTrigger> jobs = [
            SELECT NextFireTime 
            FROM CronTrigger 
            WHERE CronJobDetail.Name = :JOB_NAME
            LIMIT 1
        ];
        return jobs.isEmpty() ? null : jobs[0].NextFireTime;
    }
    
    /**
     * Runs the batch immediately (for testing/manual execution).
     */
    public static Id runNow() {
        return TalentPoolExpiryBatch.runNow();
    }
}


/**
 * ═══════════════════════════════════════════════════════════════════════════
 * EMAIL TEMPLATE METADATA (Deploy via Metadata API)
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * File: email/Talent_Pool_Renewal_Reminder.email
 * 
 * TASK COVERED: US-045-BE-033
 * ═══════════════════════════════════════════════════════════════════════════
 */

/*
<?xml version="1.0" encoding="UTF-8"?>
<EmailTemplate xmlns="http://soap.sforce.com/2006/04/metadata">
    <available>true</available>
    <description>Sent to candidates 30 days before their talent pool interest expires</description>
    <encodingKey>UTF-8</encodingKey>
    <name>Talent Pool Renewal Reminder</name>
    <style>freeForm</style>
    <subject>Still interested in {!Campaign.Employer__r.Name}?</subject>
    <textOnly>Hi {!Contact.FirstName},

It's been almost a year since you expressed interest in {!Campaign.Employer__r.Name}. 

Your interest will expire in 30 days. If you'd like to stay in their talent pool for future opportunities, please click the link below:

{!$Site.BaseUrl}/services/apexrest/api/talent-pool/renew?token={!CampaignMember.Renewal_Token__c}

Not interested anymore? No action needed - your membership will simply expire.

---
This email was sent because you previously expressed interest in {!Campaign.Employer__r.Name}.</textOnly>
    <type>campaignMember</type>
</EmailTemplate>
*/


/**
 * ═══════════════════════════════════════════════════════════════════════════
 * CUSTOM FIELDS REQUIRED ON CampaignMember
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * Deploy these fields to CampaignMember object:
 * 
 * 1. Reminder_Sent__c (Checkbox)
 *    - Default: false
 *    - Description: Indicates if 11-month renewal reminder was sent
 * 
 * 2. Reminder_Sent_Date__c (Date)
 *    - Description: Date when reminder email was sent
 * 
 * 3. Renewal_Count__c (Number)
 *    - Default: 0
 *    - Description: Number of times member has renewed interest
 * 
 * 4. Last_Renewal_Date__c (Date)
 *    - Description: Date of most recent renewal
 * 
 * 5. Expiry_Date__c (Date)
 *    - Description: Date when membership was expired
 * 
 * 6. Expiry_Reason__c (Text 255)
 *    - Description: Reason for expiry
 * 
 * 7. Opt_Out_Date__c (Date)
 *    - Description: Date when member opted out
 * 
 * 8. Opt_Out_Reason__c (Text 255)
 *    - Description: Reason for opting out
 * 
 * ═══════════════════════════════════════════════════════════════════════════
 */


/**
 * ═══════════════════════════════════════════════════════════════════════════
 * DEPLOYMENT SCRIPT (Run in Anonymous Apex)
 * ═══════════════════════════════════════════════════════════════════════════
 */

/*
// ============================================
// STEP 1: Schedule All Daily Batch Jobs
// ============================================

// Talent Pool Metrics - 2 AM daily
String metricsJobId = TalentPoolMetricsScheduler.scheduleDaily();
System.debug('Metrics Job ID: ' + metricsJobId);

// Talent Pool Expiry - 3 AM daily
String expiryJobId = TalentPoolExpiryScheduler.scheduleDaily();
System.debug('Expiry Job ID: ' + expiryJobId);

// Talent Pool Segmentation - Sunday 3 AM weekly
String segmentJobId = TalentPoolSegmentationScheduler.scheduleWeekly();
System.debug('Segmentation Job ID: ' + segmentJobId);

// ============================================
// STEP 2: Verify Scheduled Jobs
// ============================================

System.debug('Metrics Scheduled: ' + TalentPoolMetricsScheduler.isScheduled());
System.debug('Metrics Next Run: ' + TalentPoolMetricsScheduler.getNextRunTime());

System.debug('Expiry Scheduled: ' + TalentPoolExpiryScheduler.isScheduled());
System.debug('Expiry Next Run: ' + TalentPoolExpiryScheduler.getNextRunTime());

// ============================================
// STEP 3: (Optional) Run Immediately for Testing
// ============================================

// Run expiry batch now
// Id batchId = TalentPoolExpiryScheduler.runNow();
// System.debug('Batch Job ID: ' + batchId);

*/