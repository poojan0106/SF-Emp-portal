Id contactId = '00392000016FqJZAA0';
Id rcsAccountId = '00192000018LP80AAG';

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
    Contact testContact = new Contact(Id = contactId);
    testContact.R_ATS__Skills__c = 'Salesforce,Apex,Product Management';
    testContact.Years_Experience__c = 8;
    testContact.MailingCity = 'Sydney';
    update testContact;

    NotificationService.notifyBlakeneyMessage(
        contactId,
        'Blakeney found a new career update for you.'
    );

    NotificationService.notifyProfileReminder(contactId, 62);

    NotificationService.notifyInterviewInvitation(
        contactId,
        'RCS',
        'Senior Product Manager'
    );

    CampaignMember memberForApplication = [
        SELECT Id, Status
        FROM CampaignMember
        WHERE ContactId = :contactId
        LIMIT 1
    ];
    memberForApplication.Status = memberForApplication.Status == 'Interested' ? 'Interviewed' : 'Interested';
    update memberForApplication;

    JobCreationService.JobCreationRequest jobReq = new JobCreationService.JobCreationRequest();
    jobReq.title = 'Notification Scenario Test Job ' + String.valueOf(DateTime.now().getTime());
    jobReq.dept = 'Product';
    jobReq.loc = 'Sydney';
    jobReq.description = 'Scenario test job for notification center validation.';
    jobReq.salMin = '100000';
    jobReq.salMax = '140000';
    jobReq.type = 'Permanent';
    jobReq.deadline = String.valueOf(Date.today().addDays(30));
    jobReq.openings = '1';
    jobReq.remote = false;
    jobReq.isDraft = false;
    jobReq.accountId = rcsAccountId;

    JobCreationService.JobCreationResponse jobResponse = JobCreationService.createJobCampaign(jobReq);

    Campaign jobCampaign = new Campaign(Id = (Id) jobResponse.campaignId);
    jobCampaign.Must_Have_Skills__c = 'Salesforce,Apex';
    jobCampaign.Nice_To_Have_Skills__c = 'Product Management';
    update jobCampaign;

    CandidateMatchingService.matchCandidatesToJob((Id) jobResponse.campaignId, rcsAccountId);

    System.debug('NOTIFICATION_SCENARIO_TEST_JOB_ID=' + jobResponse.campaignId);
} finally {
    Contact restoreContact = new Contact(Id = contactId);
    restoreContact.R_ATS__Skills__c = originalSkills;
    restoreContact.Years_Experience__c = originalYears;
    restoreContact.MailingCity = originalCity;
    update restoreContact;
}
