// ========================================
// Service Class - Business Logic
// ========================================
public class JobCreationService {
  
  public static JobCreationResponse createJobCampaign(JobCreationRequest jobReq) {
      
    Id jobCampaignRecordTypeId = getJobCampaignRecordTypeId();
    
    // Create Campaign record
    Campaign campaign = new Campaign(
      RecordTypeId = jobCampaignRecordTypeId,
      Name = jobReq.title,
      Job_Title__c = jobReq.title,
      Department__c = jobReq.dept,
      Type = jobReq.type,
      Employment_Type__c = jobReq.type,
      Employer__c = jobReq.accountId,
      Status = jobReq.isDraft ? 'Planned' : 'Active',
      StartDate = Date.today(),
      EndDate = jobReq.deadline != null ? Date.valueOf(jobReq.deadline) : null,
      Description = jobReq.description,
      Is_Talent_Pool__c = true,
      Created_by_Flint__c = false,
      Created_Via__c = 'manual',
      Source__c = 'manual',
      R_ATS__No_of_openings__c = jobReq.openings,
      R_ATS__Minimum_Salary__c = jobReq.salMin != null ? Decimal.valueOf(jobReq.salMin) : null,
      R_ATS__Maximum_Salary__c = jobReq.salMax != null ? Decimal.valueOf(jobReq.salMax) : null,
      Remote_Position__c = jobReq.remote,
      R_ATS__Location__c = jobReq.remote ? 'Remote' : jobReq.loc,
      Must_Have_Skills__c = skillsToText(jobReq.skills)
    );
    
    insert campaign;
    TalentPoolService.createTalentPoolStatuses(new List<Id>{ campaign.Id });

    if (!jobReq.isDraft) {
      notifyInterestedCandidatesForNewJob(campaign, jobReq);
      CandidateMatchingService.matchCandidatesToJob(campaign.Id, jobReq.accountId);
    }
    
    return new JobCreationResponse(
      true,
      campaign.Id,
      campaign.Status,
      'Job ' + (jobReq.isDraft ? 'saved as draft' : 'published') + ' successfully'
    );
  }

  private static Id getJobCampaignRecordTypeId() {
    Schema.RecordTypeInfo info = Schema.SObjectType.Campaign
      .getRecordTypeInfosByDeveloperName()
      .get('Job_Campaign');
    if (info == null) {
      throw new AuraHandledException('Campaign Record Type Job_Campaign not found');
    }
    return info.getRecordTypeId();
  }

  private static String skillsToText(List<String> skills) {
    if (skills == null || skills.isEmpty()) return null;
    List<String> cleaned = new List<String>();
    for (String skill : skills) {
      if (String.isNotBlank(skill)) cleaned.add(skill.trim());
    }
    return cleaned.isEmpty() ? null : String.join(cleaned, ', ');
  }

  private static void notifyInterestedCandidatesForNewJob(Campaign campaign, JobCreationRequest jobReq) {
    List<Swipe_Event__c> swipes = [
      SELECT Candidate__c
      FROM Swipe_Event__c
      WHERE Employers__c = :jobReq.accountId
      AND Direction__c = 'Right'
      AND Is_Undone__c = false
      LIMIT 2000
    ];

    if (swipes.isEmpty()) return;

    Account employer = [
      SELECT Name
      FROM Account
      WHERE Id = :jobReq.accountId
      LIMIT 1
    ];

    Set<Id> candidateIds = new Set<Id>();
    for (Swipe_Event__c swipe : swipes) {
      candidateIds.add(swipe.Candidate__c);
    }

    List<NotificationService.NotificationRequest> requests = new List<NotificationService.NotificationRequest>();
    for (Id candidateId : candidateIds) {
      NotificationService.NotificationRequest request = new NotificationService.NotificationRequest();
      request.recipientId = candidateId;
      request.notificationType = 'Company_Hiring';
      request.title = 'Company you swiped is now hiring';
      request.description = employer.Name + ' posted ' + campaign.Name + ' that may fit your profile.';
      request.linkTo = '/discover-employers';
      request.priority = 'Normal';
      requests.add(request);
    }

    NotificationService.notifyMany(requests);
  }


    // ========================================
    // Wrapper Classes
    // ========================================
    
    public class JobCreationRequest {
      public String title;
      public String dept;
      public String loc;
      public String description;
      public List<String> skills;
      public String salMin;
      public String salMax;
      public String type;
      public String deadline;
      public String openings;
      public Boolean remote;
      public Boolean isDraft;
      public String accountId;
    }
    
    public class JobCreationResponse {
      public Boolean success;
      public String campaignId;
      public String status;
      public String message;
      
      public JobCreationResponse(Boolean success, String campaignId, String status, String message) {
        this.success = success;
        this.campaignId = campaignId;
        this.status = status;
        this.message = message;
      }
    }
    
    public class ErrorResponse {
      public Boolean success = false;
      public String error;
      
      public ErrorResponse(String error) {
        this.error = error;
      }
    }
}
