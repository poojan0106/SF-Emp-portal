@IsTest
private class AIOperationsInfrastructureTest {
    private class ClaudeMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"content":[{"type":"text","text":"{\\"skills\\":\\"JavaScript, Salesforce\\",\\"summary\\":\\"Useful candidate summary.\\",\\"flags\\":\\"No major risk flags detected\\",\\"marketabilityScore\\":80}"}],"usage":{"input_tokens":10,"output_tokens":15}}');
            return response;
        }
    }

    @IsTest
    static void logsClaudeCallsAndParsesStructuredData() {
        Test.setMock(HttpCalloutMock.class, new ClaudeMock());

        Test.startTest();
        Map<String, Object> data = ClaudeAPIService.extractStructuredData('CV text', 'Return JSON');
        Test.stopTest();

        System.assertEquals('JavaScript, Salesforce', String.valueOf(data.get('skills')));
    }

    @IsTest
    static void chatCallParsesResponse() {
        Test.setMock(HttpCalloutMock.class, new ClaudeMock());

        Test.startTest();
        ClaudeAPIService.ClaudeResponse response = ClaudeAPIService.chat(
            'System',
            new List<Map<String, String>>{ new Map<String, String>{ 'role' => 'user', 'content' => 'hello' } },
            0.1,
            100
        );
        Test.stopTest();

        System.assertNotEquals(null, response.content);
    }

    @IsTest
    static void retryQueueAndBatchesRun() {
        Account acct = new Account(Name = 'AI Ops Employer');
        insert acct;

        Id jobRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Campaign'
            AND DeveloperName = 'Job_Campaign'
            LIMIT 1
        ].Id;
        Campaign campaign = new Campaign(
            Name = 'AI Ops Role',
            IsActive = true,
            Status = 'Active',
            RecordTypeId = jobRecordTypeId,
            Type = 'Permanent'
        );
        campaign.put('Employer__c', acct.Id);
        campaign.put('Must_Have_Skills__c', 'JavaScript');
        campaign.put('Location_Requirement__c', 'Sydney');
        campaign.put('Job_Seniority__c', 'Junior');
        insert campaign;

        Contact con = new Contact(
            FirstName = 'AI',
            LastName = 'Ops',
            Email = 'aiops@example.com',
            Title = 'Developer',
            MailingCity = 'Sydney'
        );
        con.put('R_ATS__Skills__c', 'JavaScript');
        if (Contact.SObjectType.getDescribe().fields.getMap().containsKey('Years_Experience__c')) {
            con.put('Years_Experience__c', 2);
        }
        insert con;

        CampaignMember member = new CampaignMember(CampaignId = campaign.Id, ContactId = con.Id, Status = 'Sent');
        insert member;

        AIAPILogService.logSuccess('CV Scoring', con.Id, member.Id, 'request', 'response', 12);
        AIRetryService.enqueue(con.Id, member.Id, 'CV Scoring', 'payload', 'error');

        Test.startTest();
        Database.executeBatch(new AICVScoringBatch(), 50);
        Database.executeBatch(new MarketabilityScoreBatch(), 50);
        new AIRetryService().execute(null);
        Test.stopTest();

        CampaignMember scored = [
            SELECT AI_CV_Score__c
            FROM CampaignMember
            WHERE Id = :member.Id
        ];
        System.assertNotEquals(null, scored.AI_CV_Score__c);

        Contact refreshed = [
            SELECT Marketability_Score__c
            FROM Contact
            WHERE Id = :con.Id
        ];
        System.assertNotEquals(null, refreshed.Marketability_Score__c);
    }
}