// ============================================================================
// FILE 1: JobListingDTO.cls
// Data Transfer Objects for Job Listing Management (Interface 2.3.2)
// Maps Salesforce Campaign/CampaignMember to portal-friendly structures
// ============================================================================
public with sharing class JobListingDTO {

    // ── Main Job listing item (used in table view) ──
    public class JobSummary {
        @AuraEnabled public String id;              // ← changed from campaignId
        @AuraEnabled public String title;           // ← changed from jobTitle
        @AuraEnabled public String ref;             // ← changed from jobReference
        @AuraEnabled public String type;            // ← changed from recordType
        @AuraEnabled public String dept;            // ← changed from department
        @AuraEnabled public String seniority;
        @AuraEnabled public String location;
        @AuraEnabled public String status;
        @AuraEnabled public String campaignStatus;  // Keep internal SF status
        @AuraEnabled public Date posted;            // ← changed from postedDate
        @AuraEnabled public Date deadline;
        @AuraEnabled public Integer applicants;     // ← changed from totalApplicants
        @AuraEnabled public Integer openings;
        @AuraEnabled public Integer filled;
        @AuraEnabled public String salary;
        @AuraEnabled public String salMin;
        @AuraEnabled public String salMax;
        @AuraEnabled public Decimal billRate;
        @AuraEnabled public Decimal payRate;
        @AuraEnabled public String source;
        @AuraEnabled public String owner;           // ← changed from ownerName
        @AuraEnabled public String opportunity;     // ← changed from opportunityName
        @AuraEnabled public String account;         // ← changed from accountName
        @AuraEnabled public String accountId;
        @AuraEnabled public PipelineSummary pipeline;
        @AuraEnabled public List<String> skills;
        @AuraEnabled public Boolean isOverdue;
        @AuraEnabled public Integer daysOpen;       // Days since StartDate
    }

    // ── Pipeline counts per Campaign Member Status ──
    public class PipelineSummary {
        @AuraEnabled public Integer shortlisted = 0;     // Shortlist
        @AuraEnabled public Integer screening = 0;       // New Application / Screening
        @AuraEnabled public Integer interview1 = 0;      // Internal Interview
        @AuraEnabled public Integer interview2 = 0;      // 2nd Interview
        @AuraEnabled public Integer offered = 0;         // Offer Accepted
        @AuraEnabled public Integer placed = 0;          // Placed
        @AuraEnabled public Integer rejected = 0;        // Rejected / Withdrawn
        @AuraEnabled public Integer total = 0;
    }

    // ── Job detail view (expanded) ──
    public class JobDetail {
        @AuraEnabled public JobSummary summary;
        @AuraEnabled public String description;          // Description
        @AuraEnabled public List<PipelineCandidate> candidates;
        @AuraEnabled public List<PlacementRecord> placements;
        @AuraEnabled public List<ActivityItem> recentActivity;
        @AuraEnabled public String flintConversationId;  // Chat_Interaction__c Id
    }

    // ── Candidate card within pipeline ──
    public class PipelineCandidate {
        @AuraEnabled public String memberId;             // CampaignMember.Id
        @AuraEnabled public String contactId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String status;               // Current CM Status
        @AuraEnabled public String subStatus;            // CM Sub Status
        @AuraEnabled public Date dateAdded;
        @AuraEnabled public Integer daysInStage;
        @AuraEnabled public String notes;                // Latest notes
        @AuraEnabled public Decimal matchScore;          // Match_Score__c
        @AuraEnabled public Boolean hasResume;
    }

    // ── Placement record ──
    public class PlacementRecord {
        @AuraEnabled public String placementId;
        @AuraEnabled public String candidateName;
        @AuraEnabled public Date startDate;
        @AuraEnabled public String recordType;
        @AuraEnabled public String status;
    }

    // ── Activity feed item ──
    public class ActivityItem {
        @AuraEnabled public Datetime eventTime;
        @AuraEnabled public String eventType;            // status_change | note | email | creation
        @AuraEnabled public String description;
        @AuraEnabled public String performedBy;
    }

    // ── Create/Edit job request ──
    public class JobCreateRequest {
       @AuraEnabled public String accountId;           // Employer Account
        @AuraEnabled public String title;               // Job title
        @AuraEnabled public String type;                // ← Changed from recordType
        @AuraEnabled public String dept;                // ← Changed from department
        @AuraEnabled public String description;
        @AuraEnabled public String loc;                 // ← Changed from city (combined location)
        @AuraEnabled public Boolean remote;             // ← Changed from isRemote
        @AuraEnabled public String salMin;              // ← New: minimum salary
        @AuraEnabled public String salMax;              // ← New: maximum salary
        @AuraEnabled public Decimal billRate;
        @AuraEnabled public Decimal payRate;
        @AuraEnabled public Integer openings;
        @AuraEnabled public String deadline;            // Note: comes as string from frontend
        @AuraEnabled public String urgency;             // Low | Normal | High | Urgent
        @AuraEnabled public List<String> skills;        // ← Changed from skillNames
        @AuraEnabled public String status;
        @AuraEnabled public Boolean publishImmediately;
        
        // Legacy/unused fields - keep for backward compatibility
        @AuraEnabled public String seniority;
        @AuraEnabled public String seniorityLevel;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String postalCode;
        @AuraEnabled public String country;
    }

    // ── Filters for listing query ──
    public class JobFilter {
        @AuraEnabled public String searchTerm;
        @AuraEnabled public String status;               // All | Active | Draft | On Hold | Closed
        @AuraEnabled public String recordType;           // All | Permanent | Contract | Temporary
        @AuraEnabled public String department;
        @AuraEnabled public String sortField;            // title | posted | applicants | deadline
        @AuraEnabled public String sortDirection;        // ASC | DESC
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer pageNumber;
    }

    // ── Dashboard stats ──
    public class JobStats {
        @AuraEnabled public Integer activeJobs = 0;
        @AuraEnabled public Integer totalApplicants = 0;
        @AuraEnabled public Integer drafts = 0;
        @AuraEnabled public Integer onHold = 0;
        @AuraEnabled public Integer closedThisMonth = 0;
        @AuraEnabled public Integer totalPlacements = 0;
    }
}
