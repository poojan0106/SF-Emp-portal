/**
 * JobCampaignService
 * Creates and manages job campaigns from Flint conversations
 */
public class JobCampaignService {
    
    public static Id createFromFlint(Id accountId, Map<String,Object> jobDetails) {
        Id jobRecordTypeId = getJobCampaignRecordTypeId();
        
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
            Created_Via__c = 'flint',
            Source__c = 'flint',
            Job_Title__c = jobTitle,
            Is_Talent_Pool__c = true,
            StartDate = Date.today()
        );
        
        // Set fields from extracted data
        if (jobDetails.containsKey('seniority_level')) {
            String seniority = normalizeSeniority((String) jobDetails.get('seniority_level'));
            job.Seniority_Level__c = seniority;
            job.Job_Seniority__c = seniority;
        }
        if (jobDetails.containsKey('must_have_skills')) {
            Object skills = jobDetails.get('must_have_skills');
            job.Must_Have_Skills__c = skillsToText(skills);
        }
        if (jobDetails.containsKey('nice_to_have_skills')) {
            Object skills = jobDetails.get('nice_to_have_skills');
            job.Nice_to_Have_Skills__c = skillsToText(skills);
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
        if (jobDetails.containsKey('job_openings')) {
            job.R_ATS__No_of_openings__c = String.valueOf(jobDetails.get('job_openings'));
        }
        if (jobDetails.containsKey('urgency')) {
            job.Urgency__c = normalizeUrgency((String) jobDetails.get('urgency'));
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
            String employmentType = normalizeEmploymentType((String) jobDetails.get('Employment_Type'));
            job.Type = employmentType;
            job.Employment_Type__c = employmentType;
        }
        
        insert job;
        TalentPoolService.createTalentPoolStatuses(new List<Id>{ job.Id });
        
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

    private static String skillsToText(Object skills) {
        if (skills == null) return null;
        if (skills instanceof List<Object>) {
            List<String> parts = new List<String>();
            for (Object skill : (List<Object>) skills) {
                String value = String.valueOf(skill).trim();
                if (String.isNotBlank(value)) parts.add(value);
            }
            return String.join(parts, ', ');
        }
        return String.valueOf(skills);
    }

    private static String normalizeEmploymentType(String value) {
        String lower = String.isBlank(value) ? '' : value.toLowerCase();
        if (lower.contains('contract')) return 'Contract';
        if (lower.contains('temp')) return 'Temporary';
        return 'Permanent';
    }

    private static String normalizeSeniority(String value) {
        String lower = String.isBlank(value) ? '' : value.toLowerCase();
        if (lower.contains('executive')) return 'Executive';
        if (lower.contains('lead')) return 'Lead';
        if (lower.contains('senior')) return 'Senior';
        if (lower.contains('mid')) return 'Mid';
        if (lower.contains('junior')) return 'Junior';
        return null;
    }

    private static String normalizeUrgency(String value) {
        String lower = String.isBlank(value) ? '' : value.toLowerCase();
        if (lower.contains('critical') || lower.contains('immediate') || lower.contains('0-2')) return 'Critical';
        if (lower.contains('medium') || lower.contains('moderate') || lower.contains('2-4')) return 'Medium';
        if (lower.contains('low') || lower.contains('flexible') || lower.contains('1+')) return 'Low';
        if (lower.contains('high')) return 'High';
        return null;
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
                   Nice_to_Have_Skills__c, ExpectedRevenue, BudgetedCost, Hiring_Timeline__c,
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