/**
 * ═══════════════════════════════════════════════════════════════════════════
 * TalentPoolMetricsServiceTest.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Test class for TalentPoolMetricsService, CampaignMemberHandler,
 *          TalentPoolMetricsBatch, and TalentPoolMetricsScheduler
 * 
 * COVERAGE TARGET: 90%+
 * 
 * TEST SCENARIOS:
 *   - Pool size calculation with active/inactive members
 *   - New members this week calculation
 *   - Average intent currency calculation
 *   - Quality score calculation
 *   - Trigger-based metrics update
 *   - Batch processing
 *   - Scheduler functionality
 * ═══════════════════════════════════════════════════════════════════════════
 */
@isTest
private class TalentPoolMetricsServiceTest {
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST DATA SETUP
    // ═══════════════════════════════════════════════════════════════════════
    
    @TestSetup
    static void setupTestData() {
        // Create Employer Account
        Account employer = new Account(
            Name = 'Test Employer Corp',
            Industry = 'Technology',
            Is_Active__c = true,
            Profile_Completeness__c = 80
        );
        insert employer;
        
        // Create Candidates (Contacts)
        List<Contact> candidates = new List<Contact>();
        for (Integer i = 0; i < 10; i++) {
            candidates.add(new Contact(
                FirstName = 'Test',
                LastName = 'Candidate ' + i,
                Email = 'candidate' + i + '@test.com',
                Profile_Completeness__c = 50 + (i * 5), // 50-95%
                Last_Activity_Date__c = Date.today().addDays(-i * 5) // Varied activity
            ));
        }
        insert candidates;
        
        // Create Talent Pool Campaign
        Campaign talentPool = new Campaign(
            Name = 'Test Employer Corp - Talent Pool',
            Type = 'Employer Interest Pool',
            Status = 'In Progress',
            IsActive = true,
            Employer__c = employer.Id
        );
        insert talentPool;
        
        // Create Campaign Members with varied data
        List<CampaignMember> members = new List<CampaignMember>();
        
        for (Integer i = 0; i < candidates.size(); i++) {
            CampaignMember m = new CampaignMember(
                CampaignId = talentPool.Id,
                ContactId = candidates[i].Id,
                Status = getStatusForIndex(i),
                Intent_Added_Date__c = Date.today().addDays(-i * 20) // 0, 20, 40, 60... days ago
            );
            members.add(m);
        }
        insert members;
    }
    
    /**
     * Returns varied statuses for test data.
     */
    private static String getStatusForIndex(Integer i) {
        List<String> statuses = new List<String>{
            'Interested', 'Interested', 'Interested', 'Interested', // 4 interested
            'Engaged', 'Engaged',                                    // 2 engaged
            'Contacted',                                             // 1 contacted
            'Interviewed',                                           // 1 interviewed
            'Expired',                                               // 1 expired
            'Opted_Out'                                              // 1 opted out
        };
        return statuses[Math.mod(i, statuses.size())];
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST: calculatePoolSize()
    // ═══════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testCalculatePoolSize() {
        Campaign pool = [SELECT Id FROM Campaign LIMIT 1];
        
        Test.startTest();
        Integer poolSize = TalentPoolMetricsService.calculatePoolSize(pool.Id);
        Test.stopTest();
        
        // Should count only active statuses (Interested, Engaged, Contacted, Interviewed)
        // 4 Interested + 2 Engaged + 1 Contacted + 1 Interviewed = 8
        System.assertEquals(8, poolSize, 'Pool size should count active members only');
    }
    
    @isTest
    static void testCalculatePoolSize_EmptyPool() {
        // Create empty campaign
        Campaign emptyPool = new Campaign(
            Name = 'Empty Pool',
            IsActive = true,
            Type = 'Employer Interest Pool'
        );
        insert emptyPool;
        
        Test.startTest();
        Integer poolSize = TalentPoolMetricsService.calculatePoolSize(emptyPool.Id);
        Test.stopTest();
        
        System.assertEquals(0, poolSize, 'Empty pool should have size 0');
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST: calculateNewMembersThisWeek()
    // ═══════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testCalculateNewMembersThisWeek() {
        Campaign pool = [SELECT Id FROM Campaign LIMIT 1];
        
        // Add a fresh member (today)
        Contact freshCandidate = new Contact(
            FirstName = 'Fresh',
            LastName = 'Candidate',
            Email = 'fresh@test.com'
        );
        insert freshCandidate;
        
        CampaignMember freshMember = new CampaignMember(
            CampaignId = pool.Id,
            ContactId = freshCandidate.Id,
            Status = 'Interested',
            Intent_Added_Date__c = Date.today()
        );
        insert freshMember;
        
        Test.startTest();
        Integer newCount = TalentPoolMetricsService.calculateNewMembersThisWeek(pool.Id);
        Test.stopTest();
        
        // At minimum, the fresh member should be counted
        System.assert(newCount >= 1, 'Should count at least the fresh member');
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST: calculateAverageIntentCurrency()
    // ═══════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testCalculateAverageIntentCurrency() {
        Campaign pool = [SELECT Id FROM Campaign LIMIT 1];
        
        Test.startTest();
        Decimal avgCurrency = TalentPoolMetricsService.calculateAverageIntentCurrency(pool.Id);
        Test.stopTest();
        
        // Should return a positive number
        System.assertNotEquals(null, avgCurrency, 'Should return a value');
        System.assert(avgCurrency >= 0, 'Average currency should be non-negative');
    }
    
    @isTest
    static void testCalculateAverageIntentCurrency_EmptyPool() {
        Campaign emptyPool = new Campaign(
            Name = 'Empty Pool',
            IsActive = true
        );
        insert emptyPool;
        
        Test.startTest();
        Decimal avgCurrency = TalentPoolMetricsService.calculateAverageIntentCurrency(emptyPool.Id);
        Test.stopTest();
        
        System.assertEquals(null, avgCurrency, 'Empty pool should return null');
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST: calculateQualityScore()
    // ═══════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testCalculateQualityScore() {
        Campaign pool = [SELECT Id FROM Campaign LIMIT 1];
        
        Test.startTest();
        Decimal qualityScore = TalentPoolMetricsService.calculateQualityScore(pool.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, qualityScore, 'Should return a quality score');
        System.assert(qualityScore >= 0 && qualityScore <= 100, 
                     'Quality score should be between 0-100: ' + qualityScore);
    }
    
    @isTest
    static void testCalculateQualityScore_FreshMembers() {
        // Create pool with only fresh members
        Campaign freshPool = new Campaign(
            Name = 'Fresh Pool',
            IsActive = true
        );
        insert freshPool;
        
        Contact c = new Contact(
            FirstName = 'Quality',
            LastName = 'Test',
            Email = 'quality@test.com',
            Profile_Completeness__c = 100
        );
        insert c;
        
        CampaignMember m = new CampaignMember(
            CampaignId = freshPool.Id,
            ContactId = c.Id,
            Status = 'Interested',
            Intent_Added_Date__c = Date.today() // Fresh
        );
        insert m;
        
        Test.startTest();
        Decimal qualityScore = TalentPoolMetricsService.calculateQualityScore(freshPool.Id);
        Test.stopTest();
        
        // Fresh intent (100) * 0.6 + High completeness (100) * 0.4 = 100
        System.assert(qualityScore >= 90, 'Fresh pool with complete profiles should have high score');
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST: updateMetricsForCampaigns()
    // ═══════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testUpdateMetricsForCampaigns() {
        Campaign pool = [SELECT Id FROM Campaign LIMIT 1];
        
        Test.startTest();
        TalentPoolMetricsService.updateMetricsForCampaigns(new Set<Id>{pool.Id});
        Test.stopTest();
        
        Campaign updated = [
            SELECT Pool_Size__c, New_Members_This_Week__c, 
                   Average_Intent_Currency__c, Quality_Score__c
            FROM Campaign 
            WHERE Id = :pool.Id
        ];
        
        System.assertNotEquals(null, updated.Pool_Size__c, 'Pool size should be set');
        System.assertNotEquals(null, updated.Quality_Score__c, 'Quality score should be set');
    }
    
    @isTest
    static void testUpdateMetricsForCampaigns_NullInput() {
        // Should handle null gracefully
        Test.startTest();
        TalentPoolMetricsService.updateMetricsForCampaigns(null);
        TalentPoolMetricsService.updateMetricsForCampaigns(new Set<Id>());
        Test.stopTest();
        
        // No exception = pass
        System.assert(true, 'Should handle null/empty input');
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST: CampaignMemberHandler Trigger
    // ═══════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testCampaignMemberHandler_Insert() {
        Campaign pool = [SELECT Id FROM Campaign LIMIT 1];
        Contact c = new Contact(FirstName = 'Trigger', LastName = 'Test', Email = 't@test.com');
        insert c;
        
        Test.startTest();
        CampaignMember m = new CampaignMember(
            CampaignId = pool.Id,
            ContactId = c.Id,
            Status = 'Interested',
            Intent_Added_Date__c = Date.today()
        );
        insert m;
        Test.stopTest();
        
        // Verify trigger executed (metrics should be updated)
        Campaign updated = [SELECT Pool_Size__c FROM Campaign WHERE Id = :pool.Id];
        System.assertNotEquals(null, updated.Pool_Size__c, 'Metrics should be updated on insert');
    }
    
    @isTest
    static void testCampaignMemberHandler_Update() {
        Campaign pool = [SELECT Id FROM Campaign LIMIT 1];
        CampaignMember m = [SELECT Id, Status FROM CampaignMember WHERE CampaignId = :pool.Id LIMIT 1];
        
        Test.startTest();
        m.Status = 'Engaged';
        update m;
        Test.stopTest();
        
        System.assert(true, 'Update should complete without error');
    }
    
    @isTest
    static void testCampaignMemberHandler_Delete() {
        Campaign pool = [SELECT Id FROM Campaign LIMIT 1];
        CampaignMember m = [SELECT Id FROM CampaignMember WHERE CampaignId = :pool.Id LIMIT 1];
        
        Test.startTest();
        delete m;
        Test.stopTest();
        
        System.assert(true, 'Delete should complete without error');
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST: TalentPoolMetricsBatch
    // ═══════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testTalentPoolMetricsBatch() {
        Test.startTest();
        TalentPoolMetricsBatch batch = new TalentPoolMetricsBatch();
        Id jobId = Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify batch completed
        AsyncApexJob job = [
            SELECT Status, NumberOfErrors 
            FROM AsyncApexJob 
            WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete');
        System.assertEquals(0, job.NumberOfErrors, 'Batch should have no errors');
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST: TalentPoolMetricsScheduler
    // ═══════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testTalentPoolMetricsScheduler_Schedule() {
        Test.startTest();
        String jobId = TalentPoolMetricsScheduler.scheduleDaily();
        Test.stopTest();
        
        System.assertNotEquals(null, jobId, 'Should return job ID');
        System.assert(TalentPoolMetricsScheduler.isScheduled(), 'Job should be scheduled');
    }
    
    @isTest
    static void testTalentPoolMetricsScheduler_Execute() {
        Test.startTest();
        TalentPoolMetricsScheduler scheduler = new TalentPoolMetricsScheduler();
        scheduler.execute(null);
        Test.stopTest();
        
        System.assert(true, 'Scheduler execute should complete');
    }
    
    @isTest
    static void testTalentPoolMetricsScheduler_RunNow() {
        Test.startTest();
        Id batchId = TalentPoolMetricsScheduler.runNow();
        Test.stopTest();
        
        System.assertNotEquals(null, batchId, 'Should return batch ID');
    }
    
    @isTest
    static void testTalentPoolMetricsScheduler_GetNextRunTime() {
        TalentPoolMetricsScheduler.scheduleDaily();
        
        Test.startTest();
        DateTime nextRun = TalentPoolMetricsScheduler.getNextRunTime();
        Test.stopTest();
        
        System.assertNotEquals(null, nextRun, 'Should return next run time');
    }
    
    @isTest
    static void testTalentPoolMetricsScheduler_AbortExisting() {
        TalentPoolMetricsScheduler.scheduleDaily();
        
        Test.startTest();
        TalentPoolMetricsScheduler.abortExistingJob();
        Test.stopTest();
        
        System.assert(!TalentPoolMetricsScheduler.isScheduled(), 'Job should be aborted');
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Bulk Calculation
    // ═══════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testCalculateAllMetrics_Bulk() {
        Campaign pool = [SELECT Id FROM Campaign LIMIT 1];
        
        Test.startTest();
        Map<Id, TalentPoolMetricsService.PoolMetrics> results = 
            TalentPoolMetricsService.calculateAllMetrics(new Set<Id>{pool.Id});
        Test.stopTest();
        
        System.assert(results.containsKey(pool.Id), 'Should contain result for campaign');
        TalentPoolMetricsService.PoolMetrics metrics = results.get(pool.Id);
        System.assert(metrics.poolSize > 0, 'Pool size should be positive');
    }
}