@IsTest
private class AICVEnhancementServiceTest {
    @IsTest
    static void normalizesSkillsWithMetadataFallback() {
        String normalized = AICVEnhancementService.normalizeSkills('JS; SFDC; Apex; JS');
        System.assert(normalized.contains('JavaScript'), normalized);
        System.assert(normalized.contains('Salesforce'), normalized);
        System.assert(normalized.contains('Apex'), normalized);
    }

    @IsTest
    static void enhancesContactWithoutCvTextUsingStaticFallback() {
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Candidate',
            Email = 'candidate@example.com',
            Title = 'Developer'
        );
        con.put('R_ATS__Skills__c', 'JS; SFDC; Apex');
        insert con;

        Test.startTest();
        System.enqueueJob(new AICVEnhancementJob(con.Id));
        AICVEnhancementService.enhanceContact(con.Id);
        Test.stopTest();

        Contact updated = [
            SELECT Id, Marketability_Score__c, Skills_Original__c, Candidate_Flags__c
            FROM Contact
            WHERE Id = :con.Id
        ];
        System.assertNotEquals(null, updated.Marketability_Score__c);
        System.assertNotEquals(null, updated.Skills_Original__c);
        System.assertNotEquals(null, updated.Candidate_Flags__c);
    }
}
