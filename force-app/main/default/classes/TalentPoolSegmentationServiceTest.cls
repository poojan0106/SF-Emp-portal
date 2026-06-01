/**
 * ═══════════════════════════════════════════════════════════════════════════
 * TalentPoolSegmentationServiceTest.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Test class for Pool Segmentation functionality
 * 
 * COVERAGE TARGET: 90%+
 * 
 * CLASSES COVERED:
 *   - TalentPoolSegmentationService
 *   - TalentPoolSegmentationBatch
 *   - TalentPoolSegmentationScheduler
 *   - TalentPoolService (updated)
 * ═══════════════════════════════════════════════════════════════════════════
 */
@isTest
private class TalentPoolSegmentationServiceTest {
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST DATA SETUP
    // ═══════════════════════════════════════════════════════════════════════
    
    @TestSetup
    static void setupTestData() {
        // Create Employer
        Account employer = new Account(
            Name = 'Tech Corp',
            Industry = 'Technology',
            Is_Active__c = true,
            Profile_Completeness__c = 80
        );
        insert employer;
        
        // Create Candidates with different profiles
        List<Contact> candidates = new List<Contact>();
        
        // Developer candidate
        candidates.add(new Contact(
            FirstName = 'Dev',
            LastName = 'Candidate',
            Email = 'dev@test.com',
            Title = 'Senior Software Engineer',
            Department = 'Engineering',
            R_ATS__Skills__c = 'Java, Python, AWS, React'
        ));
        
        // Sales candidate
        candidates.add(new Contact(
            FirstName = 'Sales',
            LastName = 'Candidate',
            Email = 'sales@test.com',
            Title = 'Account Executive',
            Department = 'Sales',
            R_ATS__Skills__c = 'Salesforce, Negotiation, B2B'
        ));
        
        // Marketing candidate
        candidates.add(new Contact(
            FirstName = 'Marketing',
            LastName = 'Candidate',
            Email = 'marketing@test.com',
            Title = 'Digital Marketing Manager',
            Department = 'Marketing',
            R_ATS__Skills__c = 'SEO, Google Analytics, Content'
        ));
        
        // Finance candidate
        candidates.add(new Contact(
            FirstName = 'Finance',
            LastName = 'Candidate',
            Email = 'finance@test.com',
            Title = 'Financial Analyst',
            Department = 'Finance',
            R_ATS__Skills__c = 'Excel, Budgeting, GAAP'
        ));
        
        // Operations candidate
        candidates.add(new Contact(
            FirstName = 'Ops',
            LastName = 'Candidate',
            Email = 'ops@test.com',
            Title = 'Project Manager',
            Department = 'Operations',
            R_ATS__Skills__c = 'PMP, Jira, Process Improvement'
        ));
        
        // Generic candidate (should go to "Other")
        candidates.add(new Contact(
            FirstName = 'Generic',
            LastName = 'Candidate',
            Email = 'generic@test.com',
            Title = 'Specialist',
            Department = 'Other'
        ));
        
        insert candidates;
        
        // Create Parent Talent Pool
        Campaign parentPool = new Campaign(
            Name = 'Tech Corp - Talent Pool',
            Type = 'Employer Interest Pool',
            Pool_Type__c = 'Employer_Interest',
            Status = 'In Progress',
            IsActive = true,
            Employer__c = employer.Id
        );
        insert parentPool;
        
        // Add all candidates to parent pool
        List<CampaignMember> members = new List<CampaignMember>();
        for (Contact c : candidates) {
            members.add(new CampaignMember(
                CampaignId = parentPool.Id,
                ContactId = c.Id,
                Status = 'Interested',
                Intent_Added_Date__c = Date.today()
            ));
        }
        insert members;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TEST: Segment Determination
    // ═══════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testDetermineSegments_Developer() {
        Contact dev = [SELECT Id, Title, Department, R_ATS__Skills__c FROM Contact WHERE Email = 'dev@test.com'];
        
        Test.startTest();
        Set<String> segments = TalentPoolSegmentationService.determineSegments(dev);
        Test.stopTest();
        
        System.assert(segments.contains('Developers'), 'Developer should be in Developers segment');
    }
    
    @isTest
    static void testDetermineSegments_Sales() {
        Contact sales = [SELECT Id, Title, Department, R_ATS__Skills__c FROM Contact WHERE Email = 'sales@test.com'];
        
        Test.startTest();
        Set<String> segments = TalentPoolSegmentationService.determineSegments(sales);
        Test.stopTest();
        
        System.assert(segments.contains('Sales'), 'Sales candidate should be in Sales segment');
    }
    
    @isTest
    static void testDetermineSegments_Marketing() {
        Contact marketing = [SELECT Id, Title, Department, R_ATS__Skills__c FROM Contact WHERE Email = 'marketing@test.com'];
        
        Test.startTest();
        Set<String> segments = TalentPoolSegmentationService.determineSegments(marketing);
        Test.stopTest();
        
        System.assert(segments.contains('Marketing'), 'Marketing candidate should be in Marketing segment');
    }
    
    @isTest
    static void testDetermineSegments_Finance() {
        Contact finance = [SELECT Id, Title, Department, R_ATS__Skills__c FROM Contact WHERE Email = 'finance@test.com'];
        
        Test.startTest();
        Set<String> segments = TalentPoolSegmentationService.determineSegments(finance);
        Test.stopTest();
        
        System.assert(segments.contains('Finance'), 'Finance candidate should be in Finance segment');
    }
    
    @isTest
    static void testDetermineSegments_Operations() {
        Contact ops = [SELECT Id, Title, Department, R_ATS__Skills__c FROM Contact WHERE Email = 'ops@test.com'];
        
        Test.startTest();
        Set<String> segments = TalentPoolSegmentationService.determineSegments(ops);
        Test.stopTest();
        
        System.assert(segments.contains('Operations'), 'Ops candidate should be in Operations segment');
    }
    
    @isTest
    static void testDetermineSegments_Other() {
        Contact generic = [SELECT Id, Title, Department, R_ATS__Skills__c FROM Contact WHERE Email = 'generic@test.com'];
        
        Test.startTest();
        Set<String> segments = TalentPoolSegmentationService.determineSegments(generic);
        Test.stopTest();
        
        // Generic should have empty segments (service will default to Other)
        System.assert(segments.isEmpty() || segments.contains('Other'), 
            'Generic candidate should have no specific segment');
    }
    
    @isTest
    static void testDetermineSegments_MultipleMatches() {
        // Create candidate with multiple skill areas
        Contact multiSkill = new Contact(
            FirstName = 'Multi',
            LastName = 'Skill',
            Email = 'multi@test.com',
            Title = 'Full Stack Developer',
            R_ATS__Skills__c = 'Java, Python, Sales, Marketing, SEO'
        );
        insert multiSkill;
        
        Contact queried = [SELECT Id, Title, Department, R_ATS__Skills__c FROM Contact WHERE Id = :multiSkill.Id];
        
        Test.startTest();
        Set<String> segments = TalentPoolSegmentationService.determineSegments(queried);
        Test.stopTest();
    }
}
        
        // Should match multiple segments