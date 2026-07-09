@IsTest
private class RescueWorkflowTest {
    @TestSetup
    static void setupData() {
        Account employer = new Account(Name = 'Rescue Test Employer');
        insert employer;

        Contact candidate = new Contact(
            FirstName = 'Rescue',
            LastName = 'Candidate',
            Email = 'rescue.candidate@example.com'
        );
        insert candidate;

        Id talentPoolRecordTypeId = Schema.SObjectType.Campaign
            .getRecordTypeInfosByDeveloperName()
            .get('Talent_Pool')
            .getRecordTypeId();
        Campaign pool = new Campaign(
            Name = 'Rescue Test Pool',
            RecordTypeId = talentPoolRecordTypeId,
            IsActive = true,
            Employer__c = employer.Id,
            Is_Talent_Pool__c = true
        );
        insert pool;

        CampaignMember member = new CampaignMember(
            CampaignId = pool.Id,
            ContactId = candidate.Id,
            Status = 'Interested',
            Identity_Reveal_Status__c = 'Requested',
            Identity_Reveal_Requested_Date__c = DateTime.now().addHours(-2)
        );
        insert member;

        insert new Reveal_Request__c(
            Employer__c = employer.Id,
            Candidate__c = candidate.Id,
            CampaignMember_Id__c = String.valueOf(member.Id),
            Request_Date__c = DateTime.now().addHours(-2),
            Status__c = 'Pending',
            Reason__c = 'Test reveal request'
        );
    }

    @IsTest
    static void approveRevealUpdatesMetric() {
        CampaignMember member = [
            SELECT Id, ContactId
            FROM CampaignMember
            LIMIT 1
        ];

        Test.startTest();
        TalentPoolController.CandidateWrapper result =
            TalentPoolController.respondIdentityReveal(member.Id, member.ContactId, true);
        Test.stopTest();

        System.assertEquals('Approved', result.revealStatus);
        System.assertEquals(true, result.isUnlocked);

        Protection_Metric__c metric = [
            SELECT Reveal_Requests_Received__c, Reveals_Approved__c
            FROM Protection_Metric__c
            WHERE Candidate__c = :member.ContactId
            LIMIT 1
        ];
        System.assertEquals(1, metric.Reveal_Requests_Received__c);
        System.assertEquals(1, metric.Reveals_Approved__c);
    }

    @IsTest
    static void rescueObjectsCanBeInserted() {
        CampaignMember member = [
            SELECT Id, ContactId, Campaign.Employer__c
            FROM CampaignMember
            LIMIT 1
        ];

        insert new Rescue_Opportunity__c(
            Account__c = member.Campaign.Employer__c,
            Contact__c = member.ContactId,
            CampaignMember_Id__c = String.valueOf(member.Id),
            Interview_Date__c = DateTime.now().addDays(1),
            Interview_Type__c = 'Video',
            Status__c = 'Scheduled',
            Blakeney_Prep_Notes__c = 'Prepare impact examples.'
        );

        Rescue_Opportunity__c rescue = [
            SELECT Status__c
            FROM Rescue_Opportunity__c
            WHERE Contact__c = :member.ContactId
            LIMIT 1
        ];
        System.assertEquals('Scheduled', rescue.Status__c);
    }
}
