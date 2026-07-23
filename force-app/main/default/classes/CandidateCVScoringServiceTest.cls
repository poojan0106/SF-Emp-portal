@IsTest
private class CandidateCVScoringServiceTest {
    @IsTest
    static void scoresCampaignMember() {
        Account acct = new Account(Name = 'Score Employer');
        insert acct;

        Id jobRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Campaign'
            AND DeveloperName = 'Job_Campaign'
            LIMIT 1
        ].Id;
        Campaign campaign = new Campaign(
            Name = 'Developer Role',
            IsActive = true,
            Status = 'Active',
            RecordTypeId = jobRecordTypeId,
            Type = 'Permanent'
        );
        campaign.put('Employer__c', acct.Id);
        campaign.put('Must_Have_Skills__c', 'JavaScript, Salesforce');
        campaign.put('Nice_To_Have_Skills__c', 'Apex');
        campaign.put('Location_Requirement__c', 'Sydney');
        campaign.put('Job_Seniority__c', 'Mid');
        insert campaign;

        Contact con = new Contact(
            FirstName = 'Score',
            LastName = 'Candidate',
            Email = 'score@example.com',
            MailingCity = 'Sydney'
        );
        con.put('R_ATS__Skills__c', 'JavaScript, Salesforce, Apex');
        if (Contact.SObjectType.getDescribe().fields.getMap().containsKey('Years_Experience__c')) {
            con.put('Years_Experience__c', 4);
        }
        insert con;

        CampaignMember member = new CampaignMember(CampaignId = campaign.Id, ContactId = con.Id, Status = 'Sent');
        insert member;

        Test.startTest();
        CandidateCVScoringService.scoreCampaignMember(member.Id);
        Test.stopTest();

        CampaignMember scored = [
            SELECT AI_CV_Score__c, AI_CV_Tier__c, AI_CV_Score_Explanation__c, Combined_Score__c
            FROM CampaignMember
            WHERE Id = :member.Id
        ];
        System.assert(scored.AI_CV_Score__c > 0, 'Score should be generated');
        System.assertNotEquals(null, scored.AI_CV_Tier__c);
        System.assertNotEquals(null, scored.AI_CV_Score_Explanation__c);
        System.assertNotEquals(null, scored.Combined_Score__c);
    }
}
