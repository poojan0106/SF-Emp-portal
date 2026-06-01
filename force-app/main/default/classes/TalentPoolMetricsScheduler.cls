/**
 * ═══════════════════════════════════════════════════════════════════════════
 * FILE 2: TalentPoolMetricsScheduler.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Schedulable wrapper to run TalentPoolMetricsBatch daily at 2 AM
 * 
 * TASK COVERED: US-045-BE-025
 * 
 * USAGE:
 *   // Schedule via Anonymous Apex:
 *   TalentPoolMetricsScheduler.scheduleDaily();
 *   
 *   // Or manually:
 *   System.schedule('Talent Pool Metrics - 2AM Daily', '0 0 2 * * ?', 
 *                   new TalentPoolMetricsScheduler());
 * ═══════════════════════════════════════════════════════════════════════════
 */
public class TalentPoolMetricsScheduler implements Schedulable {
    
    /** Job name for identification */
    public static final String JOB_NAME = 'Talent Pool Metrics - Daily 2AM';
    
    /** Cron expression: 2:00 AM every day */
    public static final String CRON_DAILY_2AM = '0 0 2 * * ?';
    
    /** Batch size for processing */
    private static final Integer BATCH_SIZE = 50;
    
    /**
     * Executes the scheduled job.
     * Launches TalentPoolMetricsBatch with configured batch size.
     */
    public void execute(SchedulableContext sc) {
        TalentPoolMetricsBatch batch = new TalentPoolMetricsBatch();
        Database.executeBatch(batch, BATCH_SIZE);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // SCHEDULING HELPER METHODS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Schedules the batch to run daily at 2 AM.
     * Convenience method for easy setup.
     * 
     * @return The scheduled job ID
     */
    public static String scheduleDaily() {
        // First, abort any existing job with same name
        abortExistingJob();
        
        // Schedule new job
        return System.schedule(JOB_NAME, CRON_DAILY_2AM, new TalentPoolMetricsScheduler());
    }
    
    /**
     * Schedules the batch with a custom cron expression.
     * 
     * @param cronExpression Custom cron schedule
     * @return The scheduled job ID
     */
    public static String scheduleCustom(String cronExpression) {
        abortExistingJob();
        return System.schedule(JOB_NAME, cronExpression, new TalentPoolMetricsScheduler());
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
     * 
     * @return True if scheduled, false otherwise
     */
    public static Boolean isScheduled() {
        return ![
            SELECT Id 
            FROM CronTrigger 
            WHERE CronJobDetail.Name = :JOB_NAME
            LIMIT 1
        ].isEmpty();
    }
    
    /**
     * Gets the next scheduled run time.
     * 
     * @return Next fire time or null if not scheduled
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
     * 
     * @return The batch job ID
     */
    public static Id runNow() {
        TalentPoolMetricsBatch batch = new TalentPoolMetricsBatch();
        return Database.executeBatch(batch, BATCH_SIZE);
    }
}


/**
 * ═══════════════════════════════════════════════════════════════════════════
 * DEPLOYMENT SCRIPT (Run in Anonymous Apex)
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * // 1. Check if already scheduled
 * System.debug('Is Scheduled: ' + TalentPoolMetricsScheduler.isScheduled());
 * 
 * // 2. Schedule for daily 2 AM execution
 * String jobId = TalentPoolMetricsScheduler.scheduleDaily();
 * System.debug('Scheduled Job ID: ' + jobId);
 * 
 * // 3. Verify next run time
 * System.debug('Next Run: ' + TalentPoolMetricsScheduler.getNextRunTime());
 * 
 * // 4. (Optional) Run immediately for testing
 * // Id batchId = TalentPoolMetricsScheduler.runNow();
 * // System.debug('Batch Job ID: ' + batchId);
 * 
 * ═══════════════════════════════════════════════════════════════════════════
 */