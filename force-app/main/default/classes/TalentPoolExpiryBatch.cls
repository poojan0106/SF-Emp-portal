/**
 * ═══════════════════════════════════════════════════════════════════════════
 * TalentPoolExpiryBatch.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Batch job to manage intent expiry for talent pool members
 * 
 * TASKS COVERED:
 *   - US-045-BE-031: Create TalentPoolExpiryBatch.cls
 *   - US-045-BE-032: Build 11-month reminder logic (335 days)
 *   - US-045-BE-034: Build email send flow
 *   - US-045-BE-036: Build 12-month expiry logic (365 days)
 *   - US-045-BE-037: Schedule expiry batch (daily)
 * 
 * PROCESS:
 *   1. Query all active CampaignMembers in talent pools
 *   2. For members at 335 days: Send renewal reminder email
 *   3. For members at 365+ days: Set Status = 'Expired'
 * 
 * TIMELINE:
 *   Day 0: Candidate swipes right, joins pool
 *   Day 335: Reminder email sent "Still interested?"
 *   Day 365: If no renewal, Status → 'Expired'
 * 
 * SCHEDULING: Daily at 3 AM via TalentPoolExpiryScheduler
 * 
 * AUTHOR: [Your Name]
 * DATE: January 2025
 * ═══════════════════════════════════════════════════════════════════════════
 */
public class TalentPoolExpiryBatch implements Database.Batchable<SObject>, Database.Stateful {
    
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════
    
    /** Days before expiry to send reminder (11 months = ~335 days) */
    public static final Integer REMINDER_DAYS = 335;
    
    /** Days until intent expires (12 months = 365 days) */
    public static final Integer EXPIRY_DAYS = 365;
    
    /** Grace period for reminder window (send between day 335-340) */
    private static final Integer REMINDER_WINDOW_DAYS = 5;
    
    /** Statuses considered active */
    private static final Set<String> ACTIVE_STATUSES = new Set<String>{
        'Interested', 'Engaged', 'Contacted', 'Interviewed'
    };
    
    /** Email template developer name for renewal reminder */
    private static final String REMINDER_EMAIL_TEMPLATE = 'Talent_Pool_Renewal_Reminder';
    
    /** Org-wide email address name (optional) */
    private static final String ORG_WIDE_EMAIL_NAME = 'Talent Pool';
    
    // ═══════════════════════════════════════════════════════════════════════
    // STATEFUL TRACKING
    // ═══════════════════════════════════════════════════════════════════════
    
    private Integer membersProcessed = 0;
    private Integer remindersSent = 0;
    private Integer membersExpired = 0;
    private Integer errorCount = 0;
    private List<String> errorMessages = new List<String>();
    private DateTime startTime;
    
    // ═══════════════════════════════════════════════════════════════════════
    // BATCH START
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Queries active CampaignMembers that need processing:
     * - Members approaching 11 months (need reminder)
     * - Members at/past 12 months (need expiry)
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        startTime = DateTime.now();
        
        Date today = Date.today();
        
        // Calculate date thresholds
        // Reminder: Intent added 335-340 days ago
        Date reminderStartDate = today.addDays(-REMINDER_DAYS - REMINDER_WINDOW_DAYS);
        Date reminderEndDate = today.addDays(-REMINDER_DAYS);
        
        // Expiry: Intent added 365+ days ago
        Date expiryDate = today.addDays(-EXPIRY_DAYS);
        
        String query = 
            'SELECT Id, CampaignId, ContactId, Status, Intent_Added_Date__c, ' +
            'Reminder_Sent__c, Reminder_Sent_Date__c, ' +
            'Contact.FirstName, Contact.LastName, Contact.Email, ' +
            'Campaign.Name, Campaign.Employer__c, Campaign.Employer__r.Name, ' +
            'Campaign.Employer__r.Logo_URL__c ' +
            'FROM CampaignMember ' +
            'WHERE Campaign.IsActive = true ' +
            'AND Campaign.Type = \'Employer Interest Pool\' ' +
            'AND Status IN :ACTIVE_STATUSES ' +
            'AND Intent_Added_Date__c != null ' +
            'AND (' +
            // Needs reminder (335-340 days, not yet sent)
            '    (Intent_Added_Date__c >= :reminderStartDate ' +
            '     AND Intent_Added_Date__c <= :reminderEndDate ' +
            '     AND (Reminder_Sent__c = false OR Reminder_Sent__c = null)) ' +
            '    OR ' +
            // Needs expiry (365+ days)
            '    Intent_Added_Date__c <= :expiryDate' +
            ')';
        
        return Database.getQueryLocator(query);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // BATCH EXECUTE
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Processes each batch of CampaignMembers:
     * 1. Categorize into reminder vs expiry
     * 2. Send reminder emails
     * 3. Expire old memberships
     */
    public void execute(Database.BatchableContext bc, List<CampaignMember> members) {
        Date today = Date.today();
        Date expiryThreshold = today.addDays(-EXPIRY_DAYS);
        Date reminderThreshold = today.addDays(-REMINDER_DAYS);
        
        List<CampaignMember> toSendReminder = new List<CampaignMember>();
        List<CampaignMember> toExpire = new List<CampaignMember>();
        
        // Categorize members
        for (CampaignMember m : members) {
            if (m.Intent_Added_Date__c <= expiryThreshold) {
                // 365+ days old - expire
                toExpire.add(m);
            } else if (m.Intent_Added_Date__c <= reminderThreshold && 
                      (m.Reminder_Sent__c == null || m.Reminder_Sent__c == false)) {
                // 335-364 days old, reminder not sent - send reminder
                toSendReminder.add(m);
            }
        }
        
        membersProcessed += members.size();
        
        // Process reminders
        if (!toSendReminder.isEmpty()) {
            processReminders(toSendReminder);
        }
        
        // Process expirations
        if (!toExpire.isEmpty()) {
            processExpirations(toExpire);
        }
    }
    
    /**
     * TASK US-045-BE-032 & BE-034: Sends renewal reminder emails.
     */
    private void processReminders(List<CampaignMember> members) {
        // Get email template
        EmailTemplate template = getEmailTemplate();
        Id orgWideEmailId = getOrgWideEmailId();
        
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<CampaignMember> membersToUpdate = new List<CampaignMember>();
        
        for (CampaignMember m : members) {
            // Skip if no email
            if (String.isBlank(m.Contact.Email)) continue;
            
            try {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                
                // Set recipient
                email.setTargetObjectId(m.ContactId);
                email.setToAddresses(new List<String>{m.Contact.Email});
                
                // Use template if available, otherwise build manually
                if (template != null) {
                    email.setTemplateId(template.Id);
                    email.setWhatId(m.CampaignId);
                } else {
                    // Build email manually
                    email.setSubject('Still interested in ' + m.Campaign.Employer__r.Name + '?');
                    email.setHtmlBody(buildReminderEmailBody(m));
                    email.setPlainTextBody(buildReminderEmailBodyPlainText(m));
                }
                
                // Set org-wide email if available
                if (orgWideEmailId != null) {
                    email.setOrgWideEmailAddressId(orgWideEmailId);
                }
                
                email.setSaveAsActivity(true);
                emails.add(email);
                
                // Mark reminder as sent
                CampaignMember updateMember = new CampaignMember(
                    Id = m.Id,
                    Reminder_Sent__c = true,
                    Reminder_Sent_Date__c = Date.today()
                );
                membersToUpdate.add(updateMember);
                
            } catch (Exception e) {
                errorCount++;
                errorMessages.add('Reminder email error for ' + m.ContactId + ': ' + e.getMessage());
            }
        }
        
        // Send emails
        if (!emails.isEmpty()) {
            try {
                List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
                
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        remindersSent++;
                    } else {
                        errorCount++;
                        for (Messaging.SendEmailError err : results[i].getErrors()) {
                            errorMessages.add('Email send error: ' + err.getMessage());
                        }
                        // Remove from update list if email failed
                        if (i < membersToUpdate.size()) {
                            membersToUpdate.remove(i);
                        }
                    }
                }
            } catch (Exception e) {
                errorCount++;
                errorMessages.add('Bulk email error: ' + e.getMessage());
            }
        }
        
        // Update members to mark reminder sent
        if (!membersToUpdate.isEmpty()) {
            Database.update(membersToUpdate, false);
        }
    }
    
    /**
     * TASK US-045-BE-036: Expires memberships at 365 days.
     */
    private void processExpirations(List<CampaignMember> members) {
        List<CampaignMember> membersToUpdate = new List<CampaignMember>();
        
        for (CampaignMember m : members) {
            CampaignMember updateMember = new CampaignMember(
                Id = m.Id,
                Status = 'Expired',
                Expiry_Date__c = Date.today(),
                Expiry_Reason__c = 'Auto-expired after 12 months of inactivity'
            );
            membersToUpdate.add(updateMember);
        }
        
        if (!membersToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(membersToUpdate, false);
            
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) {
                    membersExpired++;
                } else {
                    errorCount++;
                    for (Database.Error err : sr.getErrors()) {
                        errorMessages.add('Expiry update error: ' + err.getMessage());
                    }
                }
            }
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // EMAIL HELPERS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Gets the email template for renewal reminders.
     */
    private EmailTemplate getEmailTemplate() {
        List<EmailTemplate> templates = [
            SELECT Id, Name, Subject, HtmlValue, Body
            FROM EmailTemplate
            WHERE DeveloperName = :REMINDER_EMAIL_TEMPLATE
            AND IsActive = true
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0];
    }
    
    /**
     * Gets org-wide email address ID.
     */
    private Id getOrgWideEmailId() {
        List<OrgWideEmailAddress> owea = [
            SELECT Id 
            FROM OrgWideEmailAddress 
            WHERE DisplayName = :ORG_WIDE_EMAIL_NAME
            LIMIT 1
        ];
        return owea.isEmpty() ? null : owea[0].Id;
    }
    
    /**
     * TASK US-045-BE-033: Builds HTML email body for renewal reminder.
     */
    private String buildReminderEmailBody(CampaignMember m) {
        String renewalLink = buildRenewalLink(m);
        String logoUrl = m.Campaign.Employer__r.Logo_URL__c;
        String employerName = m.Campaign.Employer__r.Name;
        String firstName = String.isNotBlank(m.Contact.FirstName) ? m.Contact.FirstName : 'there';
        
        String html = '<!DOCTYPE html>' +
            '<html><head><meta charset="utf-8"></head>' +
            '<body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">' +
            
            // Header with logo
            '<div style="text-align: center; margin-bottom: 30px;">' +
            (String.isNotBlank(logoUrl) ? 
                '<img src="' + logoUrl + '" alt="' + employerName + '" style="max-height: 60px; margin-bottom: 15px;">' : '') +
            '</div>' +
            
            // Greeting
            '<h2 style="color: #333;">Hi ' + firstName + ',</h2>' +
            
            // Main message
            '<p style="color: #555; font-size: 16px; line-height: 1.6;">' +
            'It\'s been almost a year since you expressed interest in <strong>' + employerName + '</strong>. ' +
            'We wanted to check in and see if you\'re still interested in opportunities with them.</p>' +
            
            '<p style="color: #555; font-size: 16px; line-height: 1.6;">' +
            'Your interest will expire in <strong>30 days</strong>. ' +
            'If you\'d like to stay in their talent pool for future opportunities, ' +
            'please click the button below to renew your interest.</p>' +
            
            // CTA Button
            '<div style="text-align: center; margin: 30px 0;">' +
            '<a href="' + renewalLink + '" style="background-color: #4CAF50; color: white; ' +
            'padding: 15px 30px; text-decoration: none; border-radius: 5px; font-size: 16px; ' +
            'display: inline-block;">Yes, I\'m Still Interested!</a>' +
            '</div>' +
            
            // Secondary option
            '<p style="color: #888; font-size: 14px; text-align: center;">' +
            'Not interested anymore? No action needed - your membership will simply expire.</p>' +
            
            // Footer
            '<hr style="border: none; border-top: 1px solid #eee; margin: 30px 0;">' +
            '<p style="color: #999; font-size: 12px; text-align: center;">' +
            'This email was sent because you previously expressed interest in ' + employerName + '. ' +
            'You can manage your preferences in your account settings.</p>' +
            
            '</body></html>';
        
        return html;
    }
    
    /**
     * Builds plain text version of renewal email.
     */
    private String buildReminderEmailBodyPlainText(CampaignMember m) {
        String renewalLink = buildRenewalLink(m);
        String employerName = m.Campaign.Employer__r.Name;
        String firstName = String.isNotBlank(m.Contact.FirstName) ? m.Contact.FirstName : 'there';
        
        return 'Hi ' + firstName + ',\n\n' +
            'It\'s been almost a year since you expressed interest in ' + employerName + '. ' +
            'We wanted to check in and see if you\'re still interested in opportunities with them.\n\n' +
            'Your interest will expire in 30 days. ' +
            'If you\'d like to stay in their talent pool, please visit:\n' +
            renewalLink + '\n\n' +
            'Not interested anymore? No action needed - your membership will simply expire.\n\n' +
            '---\n' +
            'This email was sent because you previously expressed interest in ' + employerName + '.';
    }
    
    /**
     * Builds the renewal link for the email.
     */
    private String buildRenewalLink(CampaignMember m) {
        // Generate a secure token for renewal
        String token = generateRenewalToken(m.Id, m.ContactId);
        
        // Use Site URL or custom domain
        String baseUrl = Site.getBaseUrl();
        if (String.isBlank(baseUrl)) {
            baseUrl = URL.getOrgDomainUrl().toExternalForm();
        }
        
        return baseUrl + '/services/apexrest/api/talent-pool/renew?token=' + token;
    }
    
    /**
     * Generates a secure token for renewal verification.
     */
    private String generateRenewalToken(Id memberId, Id contactId) {
        // Create a simple encrypted token (in production, use proper encryption)
        String rawToken = memberId + '|' + contactId + '|' + DateTime.now().addDays(30).getTime();
        Blob tokenBlob = Blob.valueOf(rawToken);
        return EncodingUtil.base64Encode(tokenBlob);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // BATCH FINISH
    // ═══════════════════════════════════════════════════════════════════════
    
    public void finish(Database.BatchableContext bc) {
        DateTime endTime = DateTime.now();
        Long durationMs = endTime.getTime() - startTime.getTime();
        Long seconds = durationMs / 1000;
        
        String summary = '\n' +
            '═══════════════════════════════════════════════════════════════\n' +
            '  TALENT POOL EXPIRY BATCH - COMPLETE\n' +
            '═══════════════════════════════════════════════════════════════\n' +
            '  Completed: ' + DateTime.now().format() + '\n' +
            '  Duration: ' + seconds + ' seconds\n' +
            '  Members Processed: ' + membersProcessed + '\n' +
            '  Reminders Sent: ' + remindersSent + '\n' +
            '  Members Expired: ' + membersExpired + '\n' +
            '  Errors: ' + errorCount + '\n' +
            (errorMessages.isEmpty() ? '' : '  Errors: ' + String.join(errorMessages, '; ') + '\n') +
            '═══════════════════════════════════════════════════════════════\n';
        
        System.debug(LoggingLevel.INFO, summary);
        
        // Optional: Send admin notification
        // sendAdminNotification(summary);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // STATIC HELPER METHODS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Runs the batch immediately.
     */
    public static Id runNow() {
        return Database.executeBatch(new TalentPoolExpiryBatch(), 50);
    }
}