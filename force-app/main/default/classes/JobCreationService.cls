// ========================================
// Service Class - Business Logic
// ========================================
public class JobCreationService {
  
  public static JobCreationResponse createJobCampaign(JobCreationRequest jobReq) {
      
      // Map job types to their corresponding Record Type DeveloperNames
    Map<String, String> typeToRecordTypeMap = new Map<String, String>{
      'Permanent' => 'Permanent',
      'Temporary' => 'AdHoc',
      'Contract' => 'Contract'
      // Add more mappings as needed
    };
    
    String rtDeveloperName = typeToRecordTypeMap.get(jobReq.type);
    if (rtDeveloperName == null) {
      System.debug('Invalid job type: ' + jobReq.type);
    }
      
      // Get the Record Type based on the type field (e.g., "Permanent", "Contract", etc.)
    RecordType rt = [SELECT Id FROM RecordType 
                     WHERE SObjectType = 'Campaign' 
                     AND DeveloperName = :rtDeveloperName
                     LIMIT 1];
      
      if (rt == null) {
      System.debug('Record Type not found for type: ' + jobReq.type);
    }
    
    // Create Campaign record
    Campaign campaign = new Campaign(
      RecordTypeId = rt.Id,
      Name = jobReq.title,
      Department__c = jobReq.dept,
      Type = jobReq.type,
      Employer__c = jobReq.accountId,
      Status = jobReq.isDraft ? 'Planned' : 'Active',
      StartDate = Date.today(),
      EndDate = jobReq.deadline != null ? Date.valueOf(jobReq.deadline) : null,
      Description = jobReq.description,
      R_ATS__No_of_openings__c = jobReq.openings,
      R_ATS__Minimum_Salary__c = jobReq.salMin != null ? Decimal.valueOf(jobReq.salMin) : null,
      R_ATS__Maximum_Salary__c = jobReq.salMax != null ? Decimal.valueOf(jobReq.salMax) : null,
      Remote_Position__c = jobReq.remote,
      R_ATS__Location__c = jobReq.remote ? 'Remote' : jobReq.loc
    );
    
    insert campaign;
    
    return new JobCreationResponse(
      true,
      campaign.Id,
      campaign.Status,
      'Job ' + (jobReq.isDraft ? 'saved as draft' : 'published') + ' successfully'
    );
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