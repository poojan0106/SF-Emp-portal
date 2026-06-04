Id contactId = '00392000016FqJZAA0';
Id employerAccountId = '001920000174XgpAAE';

Contact originalContact = [
    SELECT Id, R_ATS__Skills__c, Years_Experience__c, MailingCity
    FROM Contact
    WHERE Id = :contactId
    LIMIT 1
];

String originalSkills = originalContact.R_ATS__Skills__c;
Decimal originalYears = originalContact.Years_Experience__c;
String originalCity = originalContact.MailingCity;

try {
    update new Contact(
        Id = contactId,
        R_ATS__Skills__c = 'Salesforce,Apex,Product Management',
        Years_Experience__c = 8,
        MailingCity = 'Sydney'
    );

    JobCreationService.JobCreationRequest jobReq = new JobCreationService.JobCreationRequest();
    jobReq.title = 'Job Match Scenario Test ' + String.valueOf(DateTime.now().getTime());
    jobReq.dept = 'Product';
    jobReq.loc = 'Sydney';
    jobReq.description = 'Scenario test job for job match notification validation.';
    jobReq.salMin = '100000';
    jobReq.salMax = '140000';
    jobReq.type = 'Permanent';
    jobReq.deadline = String.valueOf(Date.today().addDays(30));
    jobReq.openings = '1';
    jobReq.remote = false;
    jobReq.isDraft = false;
    jobReq.accountId = employerAccountId;

    JobCreationService.JobCreationResponse jobResponse = JobCreationService.createJobCampaign(jobReq);

    update new Campaign(
        Id = (Id) jobResponse.campaignId,
        Must_Have_Skills__c = 'Salesforce,Apex',
        Nice_To_Have_Skills__c = 'Product Management'
    );

    CandidateMatchingService.matchCandidatesToJob((Id) jobResponse.campaignId, employerAccountId);

    System.debug('JOB_MATCH_TEST_JOB_ID=' + jobResponse.campaignId);
} finally {
    update new Contact(
        Id = contactId,
        R_ATS__Skills__c = originalSkills,
        Years_Experience__c = originalYears,
        MailingCity = originalCity
    );
}
