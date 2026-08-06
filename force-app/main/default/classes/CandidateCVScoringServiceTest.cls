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

    @IsTest
    static void biasSignalsDoNotChangeScore() {
        Account acct = new Account(Name = 'Bias Employer');
        insert acct;

        Id jobRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Campaign'
            AND DeveloperName = 'Job_Campaign'
            LIMIT 1
        ].Id;
        Campaign campaign = new Campaign(
            Name = 'Bias Safe Role',
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

        Contact first = new Contact(
            FirstName = 'Alex',
            LastName = 'Candidate',
            Email = 'bias1@example.com',
            MailingCity = 'Sydney',
            Description = 'Male candidate from famous university.'
        );
        Contact second = new Contact(
            FirstName = 'Aisha',
            LastName = 'Candidate',
            Email = 'bias2@example.com',
            MailingCity = 'Sydney',
            Description = 'Female candidate from regional university.'
        );
        for (Contact con : new List<Contact>{ first, second }) {
            con.put('R_ATS__Skills__c', 'JavaScript, Salesforce, Apex');
            if (Contact.SObjectType.getDescribe().fields.getMap().containsKey('Years_Experience__c')) {
                con.put('Years_Experience__c', 4);
            }
        }
        insert new List<Contact>{ first, second };

        CampaignMember firstMember = new CampaignMember(CampaignId = campaign.Id, ContactId = first.Id, Status = 'Sent');
        CampaignMember secondMember = new CampaignMember(CampaignId = campaign.Id, ContactId = second.Id, Status = 'Sent');
        insert new List<CampaignMember>{ firstMember, secondMember };

        Test.startTest();
        CandidateCVScoringService.scoreCampaignMember(firstMember.Id);
        CandidateCVScoringService.scoreCampaignMember(secondMember.Id);
        Test.stopTest();

        Map<Id, CampaignMember> scored = new Map<Id, CampaignMember>([
            SELECT AI_CV_Score__c, AI_CV_Tier__c
            FROM CampaignMember
            WHERE Id IN :new Set<Id>{ firstMember.Id, secondMember.Id }
        ]);
        System.assertEquals(scored.get(firstMember.Id).AI_CV_Score__c, scored.get(secondMember.Id).AI_CV_Score__c);
        System.assertEquals(scored.get(firstMember.Id).AI_CV_Tier__c, scored.get(secondMember.Id).AI_CV_Tier__c);
    }
}