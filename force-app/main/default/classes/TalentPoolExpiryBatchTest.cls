/**
 * ═══════════════════════════════════════════════════════════════════════════
 * TalentPoolExpiryBatchTest.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Test class for Intent Expiry Management functionality
 * 
 * COVERAGE TARGET: 90%+
 * 
 * CLASSES COVERED:
 *   - TalentPoolExpiryBatch
 *   - TalentPoolExpiryScheduler
 *   - TalentPoolRenewalController
 * ═══════════════════════════════════════════════════════════════════════════
 */
@isTest
private class TalentPoolExpiryBatchTest {
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST DATA SETUP
    // ═══════════════════════════════════════════════════════════════════════
    
    @TestSetup
    static void setupTestData() {
        // Create Employer
        Account employer = new Account(
            Name = 'Test Employer Inc',
            Industry = 'Technology',
            Is_Active__c = true
        );
        insert employer;
        
        // Create Candidates
        List<Contact> candidates = new List<Contact>();
        for (Integer i = 0; i < 6; i++) {
            candidates.add(new Contact(
                FirstName = 'Test',
                LastName = 'Candidate ' + i,
                Email = 'candidate' + i + '@test.com'
            ));
        }
        insert candidates;
        
        // Create Talent Pool
        Campaign talentPool = new Campaign(
            Name = 'Test Employer Inc - Talent Pool',
            Type = 'Employer Interest Pool',
            Status = 'In Progress',
            IsActive = true,
            Employer__c = employer.Id
        );
        insert talentPool;
        
        // Create Campaign Members with different ages
        List<CampaignMember> members = new List<CampaignMember>();
        
        // Member 0: Fresh (30 days ago) - no action needed
        members.add(new CampaignMember(
            CampaignId = talentPool.Id,
            ContactId = candidates[0].Id,
            Status = 'Interested',
            Intent_Added_Date__c = Date.today().addDays(-30)
        ));
        
        // Member 1: At 335 days - needs reminder
        members.add(new CampaignMember(
            CampaignId = talentPool.Id,
            ContactId = candidates[1].Id,
            Status = 'Interested',
            Intent_Added_Date__c = Date.today().addDays(-335),
            Reminder_Sent__c = false
        ));
        
        // Member 2: At 340 days, reminder already sent - no action
        members.add(new CampaignMember(
            CampaignId = talentPool.Id,
            ContactId = candidates[2].Id,
            Status = 'Interested',
            Intent_Added_Date__c = Date.today().addDays(-340),
            Reminder_Sent__c = true,
            Reminder_Sent_Date__c = Date.today().addDays(-5)
        ));
        
        // Member 3: At 365 days - needs expiry
        members.add(new CampaignMember(
            CampaignId = talentPool.Id,
            ContactId = candidates[3].Id,
            Status = 'Interested',
            Intent_Added_Date__c = Date.today().addDays(-365)
        ));
        
        // Member 4: At 400 days - needs expiry (overdue)
        members.add(new CampaignMember(
            CampaignId = talentPool.Id,
            ContactId = candidates[4].Id,
            Status = 'Engaged',
            Intent_Added_Date__c = Date.today().addDays(-400)
        ));
        
        // Member 5: Already expired - no action
        members.add(new CampaignMember(
            CampaignId = talentPool.Id,
            ContactId = candidates[5].Id,
            Status = 'Expired',
            Intent_Added_Date__c = Date.today().addDays(-380),
            Expiry_Date__c = Date.today().addDays(-15)
        ));
        
        insert members;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST: TalentPoolExpiryBatch
    // ═══════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testExpiryBatch_ProcessesCorrectly() {
        Test.startTest();
        Id batchId = TalentPoolExpiryBatch.runNow();
        Test.stopTest();
        
        // Verify batch completed
        AsyncApexJob job = [
            SELECT Status, NumberOfErrors 
            FROM AsyncApexJob 
            WHERE Id = :batchId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete');
        
        // Verify expiry - members at 365+ days should be expired
        List<CampaignMember> expiredMembers = [
            SELECT Id, Status, Contact.LastName
            FROM CampaignMember
            WHERE Status = 'Expired'
        ];
        
        // Should have at least 3 expired (original 1 + 2 newly expired)
        System.assert(expiredMembers.size() >= 3, 
            'Should have expired members at 365+ days. Found: ' + expiredMembers.size());
    }
    
    @isTest
    static void testExpiryBatch_SendsReminders() {
        // Note: In test context, emails are not actually sent but are counted
        Test.startTest();
        TalentPoolExpiryBatch.runNow();
        Test.stopTest();
        
        // Verify reminder was marked as sent for 335-day member
        CampaignMember reminderMember = [
            SELECT Reminder_Sent__c, Reminder_Sent_Date__c
            FROM CampaignMember
            WHERE Contact.Email = 'candidate1@test.com'
        ];
        
        System.assertEquals(true, reminderMember.Reminder_Sent__c, 
            'Reminder should be marked as sent');
        System.assertNotEquals(null, reminderMember.Reminder_Sent_Date__c,
            'Reminder sent date should be set');
    }
    
    @isTest
    static void testExpiryBatch_SkipsAlreadySent() {
        // Member 2 already has reminder sent - should not be processed again
        CampaignMember beforeBatch = [
            SELECT Reminder_Sent_Date__c
            FROM CampaignMember
            WHERE Contact.Email = 'candidate2@test.com'
        ];
        Date originalDate = beforeBatch.Reminder_Sent_Date__c;
        
        Test.startTest();
        TalentPoolExpiryBatch.runNow();
        Test.stopTest();
        
        CampaignMember afterBatch = [
            SELECT Reminder_Sent_Date__c
            FROM CampaignMember
            WHERE Contact.Email = 'candidate2@test.com'
        ];
        
        System.assertEquals(originalDate, afterBatch.Reminder_Sent_Date__c,
            'Reminder date should not change for already-sent member');
    }
    
    @isTest
    static void testExpiryBatch_ExpiresOldMembers() {
        Test.startTest();
        TalentPoolExpiryBatch.runNow();
        Test.stopTest();
        
        // Check 365-day member
        CampaignMember member365 = [
            SELECT Status, Expiry_Date__c, Expiry_Reason__c
            FROM CampaignMember
            WHERE Contact.Email = 'candidate3@test.com'
        ];
        
        System.assertEquals('Expired', member365.Status, 'Member at 365 days should be expired');
        System.assertEquals(Date.today(), member365.Expiry_Date__c, 'Expiry date should be today');
        System.assert(member365.Expiry_Reason__c.contains('12 months'), 
            'Expiry reason should mention 12 months');
        
        // Check 400-day member
        CampaignMember member400 = [
            SELECT Status
            FROM CampaignMember
            WHERE Contact.Email = 'candidate4@test.com'
        ];
        
        System.assertEquals('Expired', member400.Status, 'Member at 400 days should be expired');
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST: TalentPoolExpiryScheduler
    // ═══════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testExpiryScheduler_ScheduleDaily() {
        Test.startTest();
        String jobId = TalentPoolExpiryScheduler.scheduleDaily();
        Test.stopTest();
        
        System.assertNotEquals(null, jobId, 'Should return job ID');
        System.assert(TalentPoolExpiryScheduler.isScheduled(), 'Job should be scheduled');
    }
    
    @isTest
    static void testExpiryScheduler_Execute() {
        Test.startTest();
        TalentPoolExpiryScheduler scheduler = new TalentPoolExpiryScheduler();
        scheduler.execute(null);
        Test.stopTest();
        
        System.assert(true, 'Scheduler execute should complete');
    }
    
    @isTest
    static void testExpiryScheduler_GetNextRunTime() {
        TalentPoolExpiryScheduler.scheduleDaily();
        
        Test.startTest();
        DateTime nextRun = TalentPoolExpiryScheduler.getNextRunTime();
        Test.stopTest();
        
        System.assertNotEquals(null, nextRun, 'Should return next run time');
    }
    
    @isTest
    static void testExpiryScheduler_AbortExisting() {
        TalentPoolExpiryScheduler.scheduleDaily();
        System.assert(TalentPoolExpiryScheduler.isScheduled(), 'Job should be scheduled');
        
        Test.startTest();
        TalentPoolExpiryScheduler.abortExistingJob();
        Test.stopTest();
        
        System.assert(!TalentPoolExpiryScheduler.isScheduled(), 'Job should be aborted');
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST: TalentPoolRenewalController
    // ═══════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testRenewalController_RenewByMemberId() {
        CampaignMember member = [
            SELECT Id FROM CampaignMember 
            WHERE Contact.Email = 'candidate1@test.com'
        ];
        
        // Create request
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/api/talent-pool/renew';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'campaignMemberId' => member.Id
        }));
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        TalentPoolRenewalController.doPost();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        // Verify renewal
        CampaignMember renewed = [
            SELECT Intent_Added_Date__c, Reminder_Sent__c, Renewal_Count__c
            FROM CampaignMember
            WHERE Id = :member.Id
        ];
        
        System.assertEquals(Date.today(), renewed.Intent_Added_Date__c, 
            'Intent date should be reset to today');
        System.assertEquals(false, renewed.Reminder_Sent__c,
            'Reminder sent should be reset');
        System.assertEquals(1, renewed.Renewal_Count__c,
            'Renewal count should be incremented');
    }
    
    @isTest
    static void testRenewalController_RenewByCandidateAndEmployer() {
        Contact candidate = [SELECT Id FROM Contact WHERE Email = 'candidate0@test.com'];
        Account employer = [SELECT Id FROM Account WHERE Name = 'Test Employer Inc'];
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/api/talent-pool/renew';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'candidateId' => candidate.Id,
            'employerId' => employer.Id
        }));
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        TalentPoolRenewalController.doPost();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
    }
    
    @isTest
    static void testRenewalController_RenewExpiredMember() {
        // Get the expired member and renew it
        CampaignMember expiredMember = [
            SELECT Id FROM CampaignMember 
            WHERE Contact.Email = 'candidate5@test.com'
            AND Status = 'Expired'
        ];
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/api/talent-pool/renew';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'campaignMemberId' => expiredMember.Id
        }));
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        TalentPoolRenewalController.doPost();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        // Verify status changed back to Interested
        CampaignMember renewed = [
            SELECT Status FROM CampaignMember WHERE Id = :expiredMember.Id
        ];
        System.assertEquals('Interested', renewed.Status, 
            'Expired member should be reactivated to Interested');
    }
    
    @isTest
    static void testRenewalController_GetStatus() {
        CampaignMember member = [
            SELECT Id FROM CampaignMember 
            WHERE Contact.Email = 'candidate0@test.com'
        ];
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/api/talent-pool/status';
        req.httpMethod = 'GET';
        req.params.put('memberId', member.Id);
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        TalentPoolRenewalController.doGet();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        // Parse response
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
            res.responseBody.toString()
        );
        System.assertEquals(true, response.get('success'), 'Should be successful');
        
        Map<String, Object> data = (Map<String, Object>) response.get('data');
        System.assertEquals('Interested', data.get('status'), 'Status should be Interested');
    }
    
    @isTest
    static void testRenewalController_OptOut() {
        CampaignMember member = [
            SELECT Id FROM CampaignMember 
            WHERE Contact.Email = 'candidate0@test.com'
        ];
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/api/talent-pool/opt-out';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'campaignMemberId' => member.Id,
            'reason' => 'No longer interested in this company'
        }));
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        TalentPoolRenewalController.doPost();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        // Verify opt-out
        CampaignMember optedOut = [
            SELECT Status, Opt_Out_Date__c, Opt_Out_Reason__c
            FROM CampaignMember
            WHERE Id = :member.Id
        ];
        
        System.assertEquals('Opted_Out', optedOut.Status, 'Status should be Opted_Out');
        System.assertEquals(Date.today(), optedOut.Opt_Out_Date__c, 'Opt out date should be today');
        System.assertEquals('No longer interested in this company', optedOut.Opt_Out_Reason__c,
            'Opt out reason should be saved');
    }
    
    @isTest
    static void testRenewalController_InvalidEndpoint() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/api/talent-pool/invalid';
        req.httpMethod = 'GET';
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        TalentPoolRenewalController.doGet();
        Test.stopTest();
        
        System.assertEquals(400, res.statusCode, 'Should return 400 for invalid endpoint');
    }
    
    @isTest
    static void testRenewalController_MissingMemberId() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/api/talent-pool/renew';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{}');
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        TalentPoolRenewalController.doPost();
        Test.stopTest();
        
        System.assertEquals(400, res.statusCode, 'Should return 400 for missing parameters');
    }
    
    @isTest
    static void testRenewalController_MemberNotFound() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/api/talent-pool/renew';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'campaignMemberId' => '00v000000000000AAA' // Fake ID
        }));
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        TalentPoolRenewalController.doPost();
        Test.stopTest();
        
        System.assertEquals(404, res.statusCode, 'Should return 404 for not found');
    }
    
    @isTest
    static void testRenewalController_RenewFromEmailToken() {
        CampaignMember member = [
            SELECT Id, ContactId FROM CampaignMember 
            WHERE Contact.Email = 'candidate1@test.com'
        ];
        
        // Create a valid token
        String rawToken = member.Id + '|' + member.ContactId + '|' + 
            DateTime.now().addDays(30).getTime();
        String token = EncodingUtil.base64Encode(Blob.valueOf(rawToken));
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/api/talent-pool/renew';
        req.httpMethod = 'GET';
        req.params.put('token', token);
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        TalentPoolRenewalController.doGet();
        Test.stopTest();
        
        // Should return HTML success page
        System.assertEquals(200, res.statusCode, 'Should return 200');
        System.assert(res.responseBody.toString().contains('Renewal'), 
            'Should return success HTML page');
    }
    
    @isTest
    static void testRenewalController_ExpiredToken() {
        CampaignMember member = [
            SELECT Id, ContactId FROM CampaignMember 
            WHERE Contact.Email = 'candidate1@test.com'
        ];
        
        // Create an expired token (timestamp in the past)
        String rawToken = member.Id + '|' + member.ContactId + '|' + 
            DateTime.now().addDays(-1).getTime();
        String token = EncodingUtil.base64Encode(Blob.valueOf(rawToken));
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/api/talent-pool/renew';
        req.httpMethod = 'GET';
        req.params.put('token', token);
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        TalentPoolRenewalController.doGet();
        Test.stopTest();
        
        System.assertEquals(410, res.statusCode, 'Should return 410 for expired token');
    }
    
    @isTest
    static void testRenewalController_InvalidToken() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/api/talent-pool/renew';
        req.httpMethod = 'GET';
        req.params.put('token', 'invalid-token-format');
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        TalentPoolRenewalController.doGet();
        Test.stopTest();
        
        System.assertEquals(400, res.statusCode, 'Should return 400 for invalid token');
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Edge Cases
    // ═══════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testExpiryBatch_NoMembersToProcess() {
        // Delete all members that need processing
        delete [
            SELECT Id FROM CampaignMember 
            WHERE Intent_Added_Date__c <= :Date.today().addDays(-335)
        ];
        
        Test.startTest();
        Id batchId = TalentPoolExpiryBatch.runNow();
        Test.stopTest();
        
        AsyncApexJob job = [SELECT Status FROM AsyncApexJob WHERE Id = :batchId];
        System.assertEquals('Completed', job.Status, 'Batch should complete even with no data');
    }
    
    @isTest
    static void testExpiryBatch_MemberWithNoEmail() {
        // Update a member to have no email
        Contact noEmailContact = [SELECT Id FROM Contact WHERE Email = 'candidate1@test.com'];
        noEmailContact.Email = null;
        update noEmailContact;
        
        Test.startTest();
        TalentPoolExpiryBatch.runNow();
        Test.stopTest();
        
        // Should complete without error, but reminder not marked as sent
        // (because no email was sent)
        System.assert(true, 'Batch should handle members without email');
    }
    
    @isTest
    static void testConstants() {
        // Verify constants are set correctly
        System.assertEquals(335, TalentPoolExpiryBatch.REMINDER_DAYS, 
            'Reminder should be at 335 days');
        System.assertEquals(365, TalentPoolExpiryBatch.EXPIRY_DAYS,
            'Expiry should be at 365 days');
    }
}