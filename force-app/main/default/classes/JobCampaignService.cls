/**
 * JobCampaignService
 * Creates and manages job campaigns from Flint conversations
 */
public class JobCampaignService {
    
    public static Id createFromFlint(Id accountId, Map<String,Object> jobDetails) {
        // Get Talent Pool record type
        Id jobRecordTypeId = getRecordTypeByEmploymentType(jobDetails);
        
        String jobTitle = (String) jobDetails.get('job_title');
        if (String.isBlank(jobTitle)) {
            jobTitle = 'New Position';
        }
        
        Campaign job = new Campaign(
            Name = jobTitle,
            RecordTypeId = jobRecordTypeId,
            Employer__c = accountId,
            IsActive = true,
            Status = 'Planned',
            Created_by_Flint__c = true,
            StartDate = Date.today()
        );
        
        // Set fields from extracted data
        if (jobDetails.containsKey('seniority_level')) {
            job.Job_Seniority__c = (String) jobDetails.get('seniority_level');
        }
        if (jobDetails.containsKey('must_have_skills')) {
            Object skills = jobDetails.get('must_have_skills');
            job.Must_Have_Skills__c = skills instanceof List<Object> ? JSON.serialize(skills) : String.valueOf(skills);
        }
        if (jobDetails.containsKey('nice_to_have_skills')) {
            Object skills = jobDetails.get('nice_to_have_skills');
            job.Nice_To_Have_Skills__c = skills instanceof List<Object> ? JSON.serialize(skills) : String.valueOf(skills);
        }
        if (jobDetails.containsKey('salary_min')) {
            job.R_ATS__Minimum_Salary__c = Decimal.valueOf(String.valueOf(jobDetails.get('salary_min')));
        }
        if (jobDetails.containsKey('salary_max')) {
            job.R_ATS__Maximum_Salary__c = Decimal.valueOf(String.valueOf(jobDetails.get('salary_max')));
        }
        if (jobDetails.containsKey('timeline_days')) {
            //job.Hiring_Timeline__c = Integer.valueOf(String.valueOf(jobDetails.get('timeline_days')));
        }
        if (jobDetails.containsKey('work_arrangement')) {
            //job.Work_Arrangement__c = (String) jobDetails.get('work_arrangement');
        }
        if (jobDetails.containsKey('location')) {
            job.Location_Requirement__c = (String) jobDetails.get('location');
        }
        if (jobDetails.containsKey('culture_notes')) {
            job.Culture_Requirements__c = (String) jobDetails.get('culture_notes');
        }
        if (jobDetails.containsKey('Employment_Type')) {
            job.Employment_Type__c = (String) jobDetails.get('Employment_Type');
        }
        
        insert job;
        
        // Trigger candidate matching asynchronously
        matchCandidatesAsync(job.Id, accountId);
        
        return job.Id;
    }
    
       /**
     * ⭐ NEW METHOD: Get Campaign Record Type ID based on Employment_Type
     * Maps Employment_Type to appropriate Record Type Developer Name
     * 
     * ⭐ UPDATED MAPPING (Your Record Types):
     * - Full-Time → Permanent
     * - Permanent → Permanent
     * - Contract → Contract
     * - Temporary → Temporary
     * - Part-Time → Permanent (default)
     * - Internship → Permanent (default)
     * - Default → Permanent (fallback)
     */
    private static Id getRecordTypeByEmploymentType(Map<String, Object> jobDetails) {
        System.debug('=== getRecordTypeByEmploymentType START ===');
        
        try {
            // ⭐ Get Employment_Type from jobDetails
            String employmentType = null;
            if (jobDetails.containsKey('Employment_Type')) {
                employmentType = (String) jobDetails.get('Employment_Type');
                System.debug('Employment_Type: ' + employmentType);
            }
            
            // ⭐ Map Employment_Type to Record Type Developer Name
            // Your Record Types: Permanent, Contract, Temporary
            String recordTypeName = 'Permanent';  // Default
            
            if (String.isNotBlank(employmentType)) {
                employmentType = employmentType.trim().toLowerCase();
                
                // ⭐ UPDATED: Maps to your actual record type names
                if (employmentType.contains('contract')) {
                    recordTypeName = 'Contract';
                    System.debug('Matched Contract employment type');
                } else if (employmentType.contains('temporary') || employmentType.contains('temp')) {
                    recordTypeName = 'AdHoc';
                    System.debug('Matched Temporary employment type');
                } else if (employmentType.contains('permanent') || employmentType.contains('full')) {
                    recordTypeName = 'Permanent';
                    System.debug('Matched Permanent employment type');
                } else {
                    recordTypeName = 'Permanent';  // Default for unknown types
                    System.debug('Unknown employment type, using Permanent as default');
                }
            }
            
            System.debug('Mapped Record Type Developer Name: ' + recordTypeName);
            
            // ⭐ Get Record Type ID from Developer Name
            Id recordTypeId = Schema.SObjectType.Campaign.getRecordTypeInfosByDeveloperName()
                .get(recordTypeName).getRecordTypeId();
            
            System.debug('Record Type ID: ' + recordTypeId);
            System.debug('=== getRecordTypeByEmploymentType COMPLETED ===');
            
            return recordTypeId;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in getRecordTypeByEmploymentType: ' + e.getMessage());
            // Fallback to Permanent record type
            System.debug('Falling back to default Permanent record type');
            return Schema.SObjectType.Campaign.getRecordTypeInfosByDeveloperName()
                .get('Permanent').getRecordTypeId();
        }
    }
    
    @AuraEnabled
    public static List<Campaign> getEmployerJobs(Id accountId, String statusFilter) {
        String query = 'SELECT Id, Name, Status, IsActive, Job_Seniority__c, ' +
            'Location_Requirement__c, Work_Arrangement__c, CreatedDate, ' +
            'Matching_Candidate_Count__c, NumberOfContacts, Timeline_Days__c ' +
            'FROM Campaign WHERE Employer_Account__c = :accountId ' +
            'AND RecordType.DeveloperName = \'Talent_Pool\'';
        
        if (String.isNotBlank(statusFilter) && statusFilter != 'All') {
            query += ' AND Status = :statusFilter';
        }
        
        query += ' ORDER BY CreatedDate DESC';
        
        return Database.query(query);
    }
    
    @AuraEnabled
    public static Campaign getJobDetails(Id jobId) {
        return [
            SELECT Id, Name, Status, IsActive, Job_Seniority__c, Must_Have_Skills__c,
                   Nice_To_Have_Skills__c, ExpectedRevenue, BudgetedCost, Hiring_Timeline__c,
                   Work_Arrangement__c, Location_Requirement__c, Culture_Requirements__c,
                   Matching_Candidate_Count__c, NumberOfContacts, Employer__c,
                   CreatedDate, Created_by_Flint__c
            FROM Campaign
            WHERE Id = :jobId
        ];
    }
    
    @AuraEnabled
    public static void updateJobStatus(Id jobId, String newStatus) {
        Campaign job = [SELECT Id, Status, IsActive FROM Campaign WHERE Id = :jobId];
        job.Status = newStatus;
        job.IsActive = (newStatus != 'Closed' && newStatus != 'Cancelled');
        update job;
    }
    
    @Future
    private static void matchCandidatesAsync(Id jobId, Id accountId) {
        CandidateMatchingService.matchCandidatesToJob(jobId, accountId);
    }
}