/**
 * ═══════════════════════════════════════════════════════════════════════════
 * TalentPoolSegmentationScheduler.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Schedulable wrapper for TalentPoolSegmentationBatch
 * 
 * SCHEDULING OPTIONS:
 *   - Weekly: Sunday at 3 AM
 *   - Custom cron expression
 * ═══════════════════════════════════════════════════════════════════════════
 */
public class TalentPoolSegmentationScheduler implements Schedulable {
    
    public static final String JOB_NAME = 'Talent Pool Segmentation - Weekly';
    public static final String CRON_WEEKLY_SUNDAY_3AM = '0 0 3 ? * SUN';
    
    public void execute(SchedulableContext sc) {
        TalentPoolSegmentationBatch batch = new TalentPoolSegmentationBatch();
        Database.executeBatch(batch, 100);
    }
    
    /**
     * Schedules weekly execution.
     */
    public static String scheduleWeekly() {
        abortExistingJob();
        return System.schedule(JOB_NAME, CRON_WEEKLY_SUNDAY_3AM, new TalentPoolSegmentationScheduler());
    }
    
    /**
     * Aborts existing scheduled job.
     */
    public static void abortExistingJob() {
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name = :JOB_NAME
        ];
        for (CronTrigger ct : jobs) {
            System.abortJob(ct.Id);
        }
    }
}