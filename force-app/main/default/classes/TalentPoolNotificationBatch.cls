/**
 * TalentPoolNotificationBatch
 * Sends weekly talent pool growth notifications to employers
 * Schedule: Every Monday at 9:00 AM
 */
global class TalentPoolNotificationBatch implements Database.Batchable<SObject>, Schedulable {
    
    global void execute(SchedulableContext sc) {
        Database.executeBatch(this, 100);
    }
    
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, Employer__c, Employer__r.Name,
                   (SELECT Id, Interest_Date__c 
                    FROM CampaignMembers 
                    WHERE Interest_Date__c >= LAST_WEEK)
            FROM Campaign
            WHERE RecordType.DeveloperName = 'Talent_Pool'
            AND Is_Talent_Pool__c = true
            AND IsActive = true
        ]);
    }
    
    global void execute(Database.BatchableContext bc, List<Campaign> pools) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        
        for (Campaign pool : pools) {
            Integer newThisWeek = pool.CampaignMembers.size();
            
            if (newThisWeek > 0) {
                // Get employer contact for email
                Contact employer = [
                    SELECT Email, FirstName
                    FROM Contact
                    WHERE AccountId = :pool.Employer__c
                    AND Is_Employer_User__c = true
                    LIMIT 1
                ];
                
                if (employer != null && String.isNotBlank(employer.Email)) {
                    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    email.setToAddresses(new List<String>{ employer.Email });
                    email.setSubject(newThisWeek + ' new candidates interested in ' + 
                                    pool.Employer__r.Name);
                    email.setHtmlBody(buildEmailBody(employer.FirstName, 
                                                     pool.Employer__r.Name, 
                                                     newThisWeek));
                    emails.add(email);
                }
            }
        }
        
        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        }
    }
    
    global void finish(Database.BatchableContext bc) {
        System.debug('Talent pool notifications sent');
    }
    
    private String buildEmailBody(String firstName, String companyName, Integer count) {
        return '<html><body>' +
            '<h2>Hi ' + firstName + ',</h2>' +
            '<p>Great news! <strong>' + count + ' new candidates</strong> have expressed ' +
            'interest in working at ' + companyName + ' this week.</p>' +
            '<p><a href="https://rezourcer.ai/talent-pools">View Your Talent Pool</a></p>' +
            '<p>Best,<br/>Flint</p>' +
            '</body></html>';
    }
}

// Schedule: System.schedule('Talent Pool Notifications', '0 0 9 ? * MON', new TalentPoolNotificationBatch());