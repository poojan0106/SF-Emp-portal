// ============================================================================
// FILE 2: JobListingService.cls
// Service layer — all business logic for Job Listing Management
// Works with existing ReZourcer ATS triggers (CampaignTrigger,
// PlacementTrigger, CampaignMemberTrigger, OpportunityTrigger)
// ============================================================================
public with sharing class JobListingService {

    // Campaign Record Type Developer Names for Job campaigns only
    private static final Set<String> JOB_RECORD_TYPES = new Set<String>{
        'Job_Campaign'
    };

    // Campaign Member Status groupings (from Custom Setting: Campaign Member Status)
    private static final Set<String> STATUS_SHORTLISTED = new Set<String>{ 'Shortlist' };
    private static final Set<String> STATUS_SCREENING   = new Set<String>{ 'New Application', 'Screening', 'Long-listed' };
    private static final Set<String> STATUS_INTERVIEW1  = new Set<String>{ 'Internal Interview' };
    private static final Set<String> STATUS_INTERVIEW2  = new Set<String>{ '2nd Interview' };
    private static final Set<String> STATUS_OFFERED     = new Set<String>{ 'Offer Accepted' };
    private static final Set<String> STATUS_PLACED      = new Set<String>{ 'Placed' };
    private static final Set<String> STATUS_REJECTED    = new Set<String>{ 'Rejected', 'Withdrawn', 'Not Suitable' };
    private static final Set<String> PIPELINE_STATUSES = new Set<String>{
        'In League',
        'Interview Requested',
        'Interview Confirmed',
        'Interview Rejected',
        'Reschedule Requested',
        'Candidate Shortlisted',
        'Candidate Rejected'
    };

    // ─────────────────────────────────────────────────────
    // GET DASHBOARD STATS
    // ─────────────────────────────────────────────────────
    public static JobListingDTO.JobStats getStats(Id accountId) {
        
        System.debug('=== JobListingService | getStats START ===');
		System.debug('Account Id: ' + accountId);
        
        JobListingDTO.JobStats stats = new JobListingDTO.JobStats();

        List<AggregateResult> results = [
            SELECT
                IsActive,
                Status,
                COUNT(Id) cnt,
                SUM(NumberOfContacts) totalMembers
            FROM Campaign
            WHERE RecordType.DeveloperName IN :JOB_RECORD_TYPES
              AND Employer__c = :accountId
            GROUP BY IsActive, Status
        ];
        
        System.debug('Aggregate Results Size: ' + results.size());

        for (AggregateResult ar : results) {
            Boolean active = (Boolean) ar.get('IsActive');
            String status = (String) ar.get('Status');
            Integer cnt = (Integer) ar.get('cnt');
            Integer members = ar.get('totalMembers') != null
                ? (Integer) ar.get('totalMembers') : 0;
            
            System.debug('Processing Aggregate Row → ' + ar);
			System.debug('Active: ' + active + ' | Status: ' + status + 
             ' | Count: ' + cnt + ' | Members: ' + members);

            stats.totalApplicants += members;

            if (active == true && status != 'Completed') {
                stats.activeJobs += cnt;
            } else if (active == false && status == 'Planned') {
                stats.drafts += cnt;
            } else if (status == 'Aborted') {
                stats.onHold += cnt;
            }
        }

        stats.totalPlacements = [
            SELECT COUNT()
            FROM CampaignMember
            WHERE Campaign.RecordType.DeveloperName IN :JOB_RECORD_TYPES
              AND Status = 'Placed'
              AND Campaign.Employer__c = :accountId
        ];
        
        System.debug('Total Placements: ' + stats.totalPlacements);
		System.debug('Final Stats: ' + stats);
		System.debug('=== JobListingService | getStats END ===');

        return stats;
    }

    // ─────────────────────────────────────────────────────
    // GET JOB LISTINGS (filtered, sorted, paginated)
    // ─────────────────────────────────────────────────────
    public static List<JobListingDTO.JobSummary> getJobs(
        Id accountId,
        JobListingDTO.JobFilter filter
    ) {
        
        System.debug('=== JobListingService | getJobs START ===');
        System.debug('AccountId: ' + accountId);
        System.debug('Filter: ' + filter);
        
        String query = 'SELECT Id, Name,R_ATS__Location__c, R_ATS__Job_Reference_Number__c, '
            + 'RecordType.DeveloperName, Department__c, Status, Type, IsActive, Seniority_Level__c, Job_Seniority__c, '
            + 'StartDate, EndDate, R_ATS__No_of_openings__c, R_ATS__Salary__c, '
            + 'R_ATS__Minimum_Salary__c, R_ATS__Maximum_Salary__c, '
            + 'R_ATS__Bill_Rate__c, R_ATS__Pay_Rate__c, Source__c, Owner.Name, Description, '
            + 'Opportunity__r.Name, Employer__c, Employer__r.Name, '
            + 'NumberOfContacts, '
            + '(SELECT Id, Status FROM CampaignMembers) '
            + 'FROM Campaign '
            + 'WHERE RecordType.DeveloperName IN :JOB_RECORD_TYPES '
            + 'AND Employer__c = :accountId ';

        // Status filter
        if (filter != null && filter.status != null && filter.status != 'All') {
            query += buildStatusFilter(filter.status);
        }

        // Record type filter
        if (filter != null && String.isNotBlank(filter.recordType)
            && filter.recordType != 'All') {
            query += 'AND RecordType.DeveloperName = \''
                + String.escapeSingleQuotes(filter.recordType) + '\' ';
        }

        // Search (title, department, reference)
        if (filter != null && String.isNotBlank(filter.searchTerm)) {
            String term = '%' + String.escapeSingleQuotes(filter.searchTerm) + '%';
            query += 'AND (Name LIKE \'' + term + '\' '
                   + 'OR Department__c LIKE \'' + term + '\' '
                   + 'OR R_ATS__Job_Reference_Number__c LIKE \'' + term + '\') ';
        }

        // Sort
        String sortField = 'StartDate';
        String sortDir = 'DESC';
        if (filter != null) {
            if (filter.sortField == 'title') sortField = 'Name';
            else if (filter.sortField == 'applicants') sortField = 'NumberOfContacts';
            else if (filter.sortField == 'deadline') sortField = 'EndDate';
            if (filter.sortDirection == 'ASC') sortDir = 'ASC';
        }
        query += 'ORDER BY ' + sortField + ' ' + sortDir + ' NULLS LAST ';

        // Pagination
        Integer pgSize = (filter != null && filter.pageSize != null)
            ? filter.pageSize : 20;
        Integer offset = (filter != null && filter.pageNumber != null)
            ? (filter.pageNumber - 1) * pgSize : 0;
        query += 'LIMIT ' + pgSize + ' OFFSET ' + offset;
        
        System.debug('Final SOQL Query: ' + query);

        List<Campaign> campaigns = Database.query(query);
        
        System.debug('Campaigns Retrieved: ' + campaigns.size());
        
		System.debug('=== JobListingService | getJobs END ===');
        return buildJobSummaries(campaigns);
    }

    // ─────────────────────────────────────────────────────
    // GET SINGLE JOB DETAIL
    // ─────────────────────────────────────────────────────
    public static JobListingDTO.JobDetail getJobDetail(Id campaignId) {
        
        System.debug('=== JobListingService | getJobDetail START ===');
		System.debug('CampaignId: ' + campaignId);
        
        Campaign c = [
            SELECT Id, Name, R_ATS__Job_Reference_Number__c,
                RecordType.DeveloperName, Department__c, Status, Type, IsActive, Seniority_Level__c, Job_Seniority__c,
                StartDate, EndDate, Description, R_ATS__No_of_openings__c,R_ATS__Location__c,
                R_ATS__Salary__c, R_ATS__Minimum_Salary__c, R_ATS__Maximum_Salary__c,
                R_ATS__Bill_Rate__c, R_ATS__Pay_Rate__c, Source__c, Must_Have_Skills__c,
                Owner.Name, Opportunity__r.Name, Employer__c,
                Employer__r.Name, NumberOfContacts
            FROM Campaign
            WHERE Id = :campaignId
              AND RecordType.DeveloperName IN :JOB_RECORD_TYPES
            LIMIT 1
        ];
        
        System.debug('Campaign Retrieved: ' + c);

        JobListingDTO.JobDetail detail = new JobListingDTO.JobDetail();
        detail.summary = buildSingleJobSummary(c);
        detail.summary.skills = parseSkillText(c.Must_Have_Skills__c);
        detail.description = c.Description;

        // ── Pipeline candidates ──
        detail.candidates = new List<JobListingDTO.PipelineCandidate>();
        List<CampaignMember> members = [
            SELECT Id, ContactId, Contact.Name, Contact.Email, Status,
                   	R_ATS__Sub_Status__c, CreatedDate, R_ATS__Notes__c, AI_CV_Score__c,
                   SystemModstamp
            FROM CampaignMember
            WHERE CampaignId = :campaignId
            AND Status IN :PIPELINE_STATUSES
            ORDER BY Status ASC, CreatedDate DESC
        ];
        
        System.debug('Pipeline Members Count: ' + members.size());

        Set<Id> contactIds = new Set<Id>();
        for (CampaignMember cm : members) {
            contactIds.add(cm.ContactId);
        }
        Set<Id> withResume = getContactsWithResume(contactIds);

        for (CampaignMember cm : members) {
            JobListingDTO.PipelineCandidate pc = new JobListingDTO.PipelineCandidate();
            pc.memberId = cm.Id;
            pc.contactId = cm.ContactId;
            pc.name = cm.Contact.Name;
            pc.email = cm.Contact.Email;
            pc.status = cm.Status;
            pc.subStatus = cm.R_ATS__Sub_Status__c;
            pc.dateAdded = cm.CreatedDate.date();
            pc.daysInStage = cm.SystemModstamp.date().daysBetween(Date.today());
            pc.notes = cm.R_ATS__Notes__c;
            pc.matchScore = cm.AI_CV_Score__c;
            pc.hasResume = withResume.contains(cm.ContactId);
            detail.candidates.add(pc);
        }

        // ── Placements ──
        detail.placements = new List<JobListingDTO.PlacementRecord>();
        for (R_ATS__Placements__c p : [
            SELECT Id, 	R_ATS__Candidate__r.Name, R_ATS__Start_Date__c,
                   RecordType.Name, R_ATS__Status__c
            FROM R_ATS__Placements__c
            WHERE R_ATS__Campaign__c = :campaignId
            ORDER BY CreatedDate DESC
        ]) {
            JobListingDTO.PlacementRecord pr = new JobListingDTO.PlacementRecord();
            pr.placementId = p.Id;
            pr.candidateName = p.R_ATS__Candidate__r.Name;
            pr.startDate = p.R_ATS__Start_Date__c;
            pr.recordType = p.RecordType.Name;
            pr.status = p.R_ATS__Status__c;
            detail.placements.add(pr);
        }

        // ── Activity feed ──
        detail.recentActivity = getActivityFeed(campaignId);

        // ── Flint conversation link ──
        List<Chat_Interaction__c> chats = [
            SELECT Id FROM Chat_Interaction__c
            WHERE Related_Campaign__c = :campaignId
              AND Agent_Type__c = 'Flint'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        detail.flintConversationId = chats.isEmpty() ? null : chats[0].Id;
        
        System.debug('Flint Conversation Id: ' + detail.flintConversationId);
		System.debug('=== JobListingService | getJobDetail END ===');

        return detail;
    }

    // ─────────────────────────────────────────────────────
    // CREATE NEW JOB (Quick Post form)
    // Creates Campaign + optional Opportunity
    // ─────────────────────────────────────────────────────
    public static Id createJob(JobListingDTO.JobCreateRequest req) {
        
        System.debug('=== JobListingService | createJob START ===');
		System.debug('Request Payload: ' + req);
        
        if (String.isBlank(req.title)) {
            throw new AuraHandledException('Job title is required');
        }
        if (String.isBlank(req.type)) {
            throw new AuraHandledException('Employment type is required');
        }

        Id rtId = getJobCampaignRecordTypeId();
        
        System.debug('RecordTypeId: ' + rtId);

        String jobRef = generateJobReference();
        
        System.debug('Generated Job Reference: ' + jobRef);

        Campaign c = new Campaign();
        c.Name = req.title;
        c.Job_Title__c = req.title;
        c.RecordTypeId = rtId;
        c.Department__c = req.dept;
        c.Description = req.description;
        c.Type = req.type;
        c.Employment_Type__c = req.type;
        c.Seniority_Level__c = normalizeSeniority(getSeniorityValue(req));
        c.Job_Seniority__c = normalizeSeniority(getSeniorityValue(req));
        c.Is_Talent_Pool__c = true;
        c.Created_by_Flint__c = false;
        c.Created_Via__c = 'manual';
        c.R_ATS__Job_Reference_Number__c = jobRef;
        c.R_ATS__No_of_openings__c = req.openings != null ? String.valueOf(req.openings) : '1';
        c.R_ATS__Minimum_Salary__c = String.isNotBlank(req.salMin) ? Decimal.valueOf(req.salMin) : null;
        c.R_ATS__Maximum_Salary__c = String.isNotBlank(req.salMax) ? Decimal.valueOf(req.salMax) : null;
        c.R_ATS__Salary__c = String.isNotBlank(req.salMax) ? Decimal.valueOf(req.salMax) : null;
        c.R_ATS__Bill_Rate__c = req.billRate;
        c.R_ATS__Pay_Rate__c = req.payRate;
        c.Urgency__c = req.urgency;
        c.Source__c = 'manual';
        c.Must_Have_Skills__c = skillsToText(req.skills);
        c.Employer__c = req.accountId;

        if (req.remote == true) {
            c.R_ATS__Location__c = 'Remote';
        } else {
            c.R_ATS__Location__c = buildLocationString(req.city, req.state);
        }

        if (req.publishImmediately == true) {
            c.IsActive = true;
            c.Status = 'Active';
            c.StartDate = Date.today();
        } else {
            c.IsActive = false;
            c.Status = 'Planned';
        }
        c.EndDate = Date.valueOf(String.valueOf(req.deadline));
        
        System.debug('Campaign To Insert: ' + c);

        insert c;
        TalentPoolService.createTalentPoolStatuses(new List<Id>{ c.Id });
        
        System.debug('Inserted Campaign Id: ' + c.Id);
        
        System.debug('Linking Skills: ' + req.skills);

        // Link Skill Codes via junction
        if (req.skills != null && !req.skills.isEmpty()) {
            linkSkillCodes(c.Id, req.skills);
        }
			
        System.debug('Creating Linked Opportunity...');
        
        // Create linked Opportunity (reverse of OpportunityTrigger)
        if (req.publishImmediately == true) {
            createLinkedOpportunity(c.Id, req);
        }
			System.debug('=== JobListingService | createJob END ===');
        return c.Id;
    }

    // ─────────────────────────────────────────────────────
    // UPDATE JOB
    // ─────────────────────────────────────────────────────
    public static void updateJob(Id campaignId, JobListingDTO.JobCreateRequest req) {
        
        System.debug('=== JobListingService | updateJob START ===');
        System.debug('CampaignId: ' + campaignId);
        System.debug('Update Request: ' + req);
        
        Campaign c = [
            SELECT Id, Name, Department__c, Description, R_ATS__Salary__c,
                   R_ATS__Minimum_Salary__c, R_ATS__Maximum_Salary__c,
                   R_ATS__Bill_Rate__c, R_ATS__Pay_Rate__c, R_ATS__No_of_openings__c,
                   Seniority_Level__c, Job_Seniority__c,
                   EndDate, Urgency__c, R_ATS__Location__c, Created_Via__c, Source__c
            FROM Campaign 
            WHERE Id = :campaignId 
            LIMIT 1
        ];
        
        System.debug('Updating Campaign: ' + c);
        
        c.RecordTypeId = getJobCampaignRecordTypeId();

        // Update all fields from request
        if (String.isNotBlank(req.title)) {
            c.Name = req.title;
            c.Job_Title__c = req.title;
            System.debug('Updated Name: ' + req.title);
        }

        if (String.isNotBlank(req.type)) {
            c.Type = req.type;
            c.Employment_Type__c = req.type;
        }

        String seniority = normalizeSeniority(getSeniorityValue(req));
        if (String.isNotBlank(seniority)) {
            c.Seniority_Level__c = seniority;
            c.Job_Seniority__c = seniority;
        }

        c.Is_Talent_Pool__c = true;
        c.Created_Via__c = String.isBlank(c.Created_Via__c) ? 'manual' : c.Created_Via__c;
        c.Source__c = String.isBlank(c.Source__c) ? 'manual' : c.Source__c;
        
        if (String.isNotBlank(req.dept)) {  // ← Changed from req.department
            c.Department__c = req.dept;
            System.debug('Updated Department: ' + req.dept);
        }
        
        if (String.isNotBlank(req.description)) {
            c.Description = req.description;
            System.debug('Updated Description: ' + req.description);
        }
        
        // Handle salary (use salMax or salMin or average)
        if (String.isNotBlank(req.salMax)) {
            try {
                c.R_ATS__Salary__c = Decimal.valueOf(req.salMax);
                c.R_ATS__Maximum_Salary__c = Decimal.valueOf(req.salMax);
                System.debug('Updated Salary (Max): ' + req.salMax);
            } catch (Exception e) {
                System.debug('ERROR parsing salMax: ' + e.getMessage());
            }
        }
        if (String.isNotBlank(req.salMin)) {
            try {
                c.R_ATS__Minimum_Salary__c = Decimal.valueOf(req.salMin);
                System.debug('Updated Salary (Min): ' + req.salMin);
            } catch (Exception e) {
                System.debug('ERROR parsing salMin: ' + e.getMessage());
            }
        }
        
        if (req.billRate != null) {
            c.R_ATS__Bill_Rate__c = req.billRate;
            System.debug('Updated Bill Rate: ' + req.billRate);
        }
        
        if (req.payRate != null) {
            c.R_ATS__Pay_Rate__c = req.payRate;
            System.debug('Updated Pay Rate: ' + req.payRate);
        }
        
        if (req.openings != null) {
            c.R_ATS__No_of_openings__c = String.valueOf(req.openings);
            System.debug('Updated Openings: ' + req.openings);
        }
        
        if (String.isNotBlank(req.deadline)) {
            try {
                c.EndDate = Date.valueOf(req.deadline);
                System.debug('Updated Deadline: ' + req.deadline);
            } catch (Exception e) {
                System.debug('ERROR parsing deadline: ' + e.getMessage());
            }
        }
        
        if (String.isNotBlank(req.urgency)) {
            c.Urgency__c = req.urgency;
            System.debug('Updated Urgency: ' + req.urgency);
        }
        
        // Handle location (Remote vs. City/State)
        if (req.remote == true) {
            c.R_ATS__Location__c = 'Remote';
            System.debug('Updated Location: Remote');
        } else if (String.isNotBlank(req.loc)) {  // ← Changed from req.city/req.state
            c.R_ATS__Location__c = req.loc;
            System.debug('Updated Location: ' + req.loc);
        }
        
        // Handle status (Draft vs Active)
        if (String.isNotBlank(req.status)) {
            if (req.status == 'Draft') {
                c.Status = 'Planned';
                System.debug('Setting as Draft');
            } else if (req.status == 'Active') {
                c.Status = 'Active';
                System.debug('Publishing job');
            } else if (req.status == 'On Hold') {
                c.Status = 'Aborted';
                System.debug('Putting job On Hold');
            } else if (req.status == 'Closed') {
                c.Status = 'Completed';
                System.debug('Closing job');
        	}
        }

        if (req.skills != null && !req.skills.isEmpty()) {
            c.Must_Have_Skills__c = skillsToText(req.skills);
        }
        
        update c;
        System.debug('Campaign Updated Successfully');
        System.debug('Campaign After Update: ' + c);
        
        // Update skills if provided
        if (req.skills != null && !req.skills.isEmpty()) {  // ← Changed from req.skillNames
            delete [SELECT Id FROM R_ATS__Campaign_Skills__c WHERE R_ATS__Campaign__c = :campaignId];
            linkSkillCodes(campaignId, req.skills);
            System.debug('Skills Updated: ' + req.skills);
        }
    }

    // ─────────────────────────────────────────────────────
    // JOB STATUS ACTIONS
    // Work WITH existing CampaignTrigger
    // ─────────────────────────────────────────────────────

    /** Publish a Draft job (Planned -> Active) */
    public static void publishJob(Id campaignId) {
        
        System.debug('=== JobListingService | publishJob START ===');
		System.debug('CampaignId: ' + campaignId);
        
        Campaign c = [
            SELECT Id, Status, IsActive, StartDate
            FROM Campaign WHERE Id = :campaignId LIMIT 1
        ];
        c.IsActive = true;
        c.Status = 'Active';
        if (c.StartDate == null) c.StartDate = Date.today();
        
        System.debug('Publishing Campaign: ' + c);
        update c;
        System.debug('Campaign Published');

        
        // Create Opportunity if none linked
        Integer oppCount = [
            SELECT COUNT() FROM Campaign
            WHERE Id = :campaignId AND Opportunity__c != null
        ];
        System.debug('Opportunity Count: ' + oppCount);
        if (oppCount == 0) {
            Campaign camp = [
                SELECT Id, Name, Type,
                       	Employer__c, R_ATS__No_of_openings__c
                FROM Campaign WHERE Id = :campaignId LIMIT 1
            ];
            JobListingDTO.JobCreateRequest stub = new JobListingDTO.JobCreateRequest();
            stub.title = camp.Name;
            stub.type = camp.Type;
            stub.accountId = camp.Employer__c;
            stub.openings = camp.R_ATS__No_of_openings__c != null
                ? Integer.valueOf(camp.R_ATS__No_of_openings__c)
                : 1;
            createLinkedOpportunity(campaignId, stub);
        }
        
        System.debug('=== JobListingService | publishJob END ===');
    }

    /** Put On Hold */
    public static void holdJob(Id campaignId) {
        update new Campaign(Id = campaignId, Status = 'Aborted', IsActive = false);
    }

    /** Reactivate from On Hold */
    public static void reactivateJob(Id campaignId) {
        update new Campaign(Id = campaignId, Status = 'Active', IsActive = true);
    }

    /** Close a job */
    public static void closeJob(Id campaignId, String closeReason) {
        Campaign c = new Campaign(Id = campaignId);
        c.Status = 'Completed';
        c.IsActive = false;
        c.Close_Reason__c = closeReason; // 'Filled' or 'Cancelled'
        update c;
    }

    /** Extend deadline */
    public static void extendDeadline(Id campaignId, Date newDeadline) {
        update new Campaign(Id = campaignId, EndDate = newDeadline);
    }

    // ─────────────────────────────────────────────────────
    // DUPLICATE JOB
    // ─────────────────────────────────────────────────────
    public static Id duplicateJob(Id campaignId) {
        
        System.debug('=== JobListingService | duplicateJob START ===');
		System.debug('Original CampaignId: ' + campaignId);
        
        Campaign orig = [
            SELECT Name, RecordTypeId, Department__c, Description,
                   R_ATS__No_of_openings__c, R_ATS__Salary__c, R_ATS__Bill_Rate__c,
                   	R_ATS__Pay_Rate__c, R_ATS__Location__c, Urgency__c, Employer__c
            FROM Campaign WHERE Id = :campaignId LIMIT 1
        ];
		
        Campaign dup = orig.clone(false, true, false, false);
        dup.Name = orig.Name + ' (Copy)';
        dup.R_ATS__Job_Reference_Number__c = (generateJobReference());
        dup.Status = 'Planned';
        dup.IsActive = false;
        dup.StartDate = Date.today();
        dup.EndDate = null;
        dup.Source__c = 'Duplicated';
        dup.Opportunity__c = null;
        System.debug('Duplicated Campaign: ' + dup);
        insert dup;
		System.debug('New Duplicate Id: ' + dup.Id);
        // Copy skill codes
        List<R_ATS__Campaign_Skills__c> origSkills = [
            SELECT R_ATS__Skill__c FROM R_ATS__Campaign_Skills__c
            WHERE R_ATS__Campaign__c = :campaignId
        ];
        if (!origSkills.isEmpty()) {
            List<R_ATS__Campaign_Skills__c> newSkills = new List<R_ATS__Campaign_Skills__c>();
            for (R_ATS__Campaign_Skills__c cs : origSkills) {
                newSkills.add(new R_ATS__Campaign_Skills__c(
                    R_ATS__Campaign__c = dup.Id,
                    R_ATS__Skill__c = cs.R_ATS__Skill__c
                ));
            }
            insert newSkills;
        }
		System.debug('=== JobListingService | duplicateJob END ===');
        return dup.Id;
    }

    // ─────────────────────────────────────────────────────
    // CANDIDATE PIPELINE MANAGEMENT
    // Updates CM Status — triggers existing PlacementTrigger
    // and CampaignMemberTrigger automatically
    // ─────────────────────────────────────────────────────

    /** Move single candidate to new stage */
    public static void updateCandidateStatus(
        Id memberId, String newStatus, String notes
    ) {
        
        System.debug('=== JobListingService | updateCandidateStatus START ===');
        System.debug('MemberId: ' + memberId);
        System.debug('New Status: ' + newStatus);
        System.debug('Notes: ' + notes);
        
        CampaignMember cm = new CampaignMember(Id = memberId);
        cm.Status = newStatus;
        if (String.isNotBlank(notes)) {
            cm.R_ATS__Notes__c = notes;
            // CampaignMemberTrigger appends with timestamp
        }
        
        System.debug('Updating CampaignMember: ' + cm);
        update cm;
        
        System.debug('CampaignMember Updated Successfully');
		System.debug('=== JobListingService | updateCandidateStatus END ===');
        // If newStatus = 'Placed', PlacementTrigger fires automatically
    }

    /** Bulk status update (mirrors Candidate Manager mass update) */
    public static void bulkUpdateCandidateStatus(
        List<Id> memberIds, String newStatus
    ) {
        
        System.debug('=== JobListingService | bulkUpdateCandidateStatus START ===');
        System.debug('MemberIds Count: ' + memberIds.size());
        System.debug('New Status: ' + newStatus);
        
        List<CampaignMember> toUpdate = new List<CampaignMember>();
        for (Id mId : memberIds) {
            toUpdate.add(new CampaignMember(Id = mId, Status = newStatus));
        }
        System.debug('Bulk Update Records: ' + toUpdate);
        update toUpdate;
        System.debug('Bulk Update Completed');
    }

    /** Add Contact to Campaign as CampaignMember */
    public static Id addCandidateToJob(
        Id campaignId, Id contactId, String initialStatus
    ) {
        
        System.debug('=== JobListingService | addCandidateToJob START ===');
        System.debug('CampaignId: ' + campaignId);
        System.debug('ContactId: ' + contactId);
        System.debug('Initial Status: ' + initialStatus);
        
        if (String.isBlank(initialStatus)) initialStatus = 'Shortlist';
        CampaignMember cm = new CampaignMember(
            CampaignId = campaignId,
            ContactId = contactId,
            Status = initialStatus
        );
        insert cm;
        System.debug('Inserted CampaignMember Id: ' + cm.Id);
		System.debug('=== JobListingService | addCandidateToJob END ===');
        return cm.Id;
    }

    /** Add from Talent Pool campaign to Job campaign */
    public static Id addFromTalentPool(Id jobCampaignId, Id poolMemberId) {
        CampaignMember poolMbr = [
            SELECT ContactId FROM CampaignMember
            WHERE Id = :poolMemberId LIMIT 1
        ];
        return addCandidateToJob(jobCampaignId, poolMbr.ContactId, 'Shortlist');
    }

    // ─────────────────────────────────────────────────────
    // BULK JOB ACTIONS
    // ─────────────────────────────────────────────────────

    public static void bulkCloseJobs(List<Id> ids, String reason) {
        List<Campaign> upd = new List<Campaign>();
        for (Id cId : ids) {
            upd.add(new Campaign(
                Id = cId, Status = 'Completed',
                IsActive = false, Close_Reason__c = reason
            ));
        }
        update upd;
    }

    public static void bulkArchiveJobs(List<Id> ids) {
        List<Campaign> upd = new List<Campaign>();
        for (Id cId : ids) {
            upd.add(new Campaign(
                Id = cId, IsActive = false, Is_Archived__c = true
            ));
        }
        update upd;
    }

    // ─────────────────────────────────────────────────────
    // PRIVATE HELPERS
    // ─────────────────────────────────────────────────────

    private static List<JobListingDTO.JobSummary> buildJobSummaries(
        List<Campaign> campaigns
    ) {
        Set<Id> cIds = new Set<Id>();
        for (Campaign c : campaigns) cIds.add(c.Id);

        Map<Id, List<String>> skillMap = getSkillsByCampaign(cIds);

        List<JobListingDTO.JobSummary> summaries =
            new List<JobListingDTO.JobSummary>();
        for (Campaign c : campaigns) {
            JobListingDTO.JobSummary s = buildSingleJobSummary(c);
            s.skills = skillMap.containsKey(c.Id)
                ? skillMap.get(c.Id) : new List<String>();
            s.pipeline = buildPipeline(c.CampaignMembers);
            s.applicants = s.pipeline.total;
            s.filled = s.pipeline.placed;
            summaries.add(s);
        }
        return summaries;
    }

    private static JobListingDTO.JobSummary buildSingleJobSummary(Campaign c) {
        
        System.debug('===== START buildSingleJobSummary =====');
        System.debug('Campaign Id: ' + c.Id);
        System.debug('Campaign Name: ' + c.Name);
        System.debug('Campaign Status: ' + c.Status);
        
        JobListingDTO.JobSummary s = new JobListingDTO.JobSummary();
        s.id = c.Id;
        s.title = c.Name;
        s.ref = String.valueOf(c.R_ATS__Job_Reference_Number__c);
        s.type = String.isNotBlank(c.Type) ? c.Type : '';
        s.seniority = String.isNotBlank(c.Seniority_Level__c) ? c.Seniority_Level__c : c.Job_Seniority__c;
        s.dept = c.Department__c;
        s.location = c.R_ATS__Location__c != null ? c.R_ATS__Location__c : '';
        s.status = derivePortalStatus(c.Status, c.IsActive);
        s.campaignStatus = c.Status;
        s.posted = c.StartDate;
        s.deadline = c.EndDate;
        s.applicants = c.NumberOfContacts != null ? c.NumberOfContacts : 0;
        s.openings = c.R_ATS__No_of_openings__c != null ? Integer.valueOf(c.R_ATS__No_of_openings__c) : 0;
        s.salary = formatSalaryRange(c.R_ATS__Minimum_Salary__c, c.R_ATS__Maximum_Salary__c, c.R_ATS__Salary__c);
        s.salMin = c.R_ATS__Minimum_Salary__c == null ? null : String.valueOf(c.R_ATS__Minimum_Salary__c.setScale(0));
        s.salMax = c.R_ATS__Maximum_Salary__c == null ? null : String.valueOf(c.R_ATS__Maximum_Salary__c.setScale(0));
        s.billRate = c.R_ATS__Bill_Rate__c;
        s.payRate = c.R_ATS__Pay_Rate__c;
        s.source = c.Source__c;
        s.owner = c.Owner.Name;
        s.opportunity = c.Opportunity__r != null
            ? c.Opportunity__r.Name : null;
        s.account = c.Employer__r != null ? c.Employer__r.Name : null;
        s.accountId = c.Employer__c;
        s.isOverdue = c.EndDate != null
            && c.EndDate < Date.today() && c.IsActive;
        s.daysOpen = c.StartDate != null
            ? c.StartDate.daysBetween(Date.today()) : 0;
        
        System.debug('Generated JobSummary DTO: ' + s);
        System.debug('Is Overdue: ' + s.isOverdue);
        System.debug('Days Open: ' + s.daysOpen);
    
        System.debug('===== END buildSingleJobSummary =====');
        return s;
    }

    /** Map SF Campaign.Status + IsActive to portal status */
    private static String derivePortalStatus(String sfSt, Boolean active) {
        if (sfSt == 'Active') return 'Active';
        if (sfSt == 'Planned') return 'Draft';
        if (sfSt == 'Sourcing') return 'Sourcing';
        if (sfSt == 'Interviewing') return 'Interviewing';
        if (sfSt == 'Offered') return 'Offered';
        if (sfSt == 'Onboarding') return 'Onboarding';
        if (sfSt == 'Aborted') return 'On Hold';
        if (sfSt == 'Completed') return 'Closed';
        return 'Draft';
    }

    private static String formatSalaryRange(Decimal minSalary, Decimal maxSalary, Decimal fallbackSalary) {
        if (minSalary != null && maxSalary != null) {
            return formatSalaryValue(minSalary) + ' - ' + formatSalaryValue(maxSalary);
        }
        if (minSalary != null) return formatSalaryValue(minSalary) + '+';
        if (maxSalary != null) return formatSalaryValue(maxSalary);
        if (fallbackSalary != null) return formatSalaryValue(fallbackSalary);
        return '';
    }

    private static String formatSalaryValue(Decimal value) {
        if (value == null) return '';
        Decimal rounded = value.setScale(0);
        if (rounded >= 1000) {
            return '$' + String.valueOf((rounded / 1000).setScale(0)) + 'k';
        }
        return '$' + String.valueOf(rounded);
    }

    private static String buildStatusFilter(String portalSt) {
        if (portalSt == 'Active')
            return 'AND Status = \'Active\' ';
        if (portalSt == 'Draft')
            return 'AND Status = \'Planned\' ';
        if (portalSt == 'On Hold')
            return 'AND Status = \'Aborted\' ';
        if (portalSt == 'Closed')
            return 'AND Status = \'Completed\' ';
        return '';
    }

    /** Aggregate CM statuses into pipeline buckets */
    private static JobListingDTO.PipelineSummary buildPipeline(
        List<CampaignMember> members
    ) {
        JobListingDTO.PipelineSummary p = new JobListingDTO.PipelineSummary();
        if (members == null) return p;

        for (CampaignMember cm : members) {
            String st = cm.Status;
            if (!PIPELINE_STATUSES.contains(st)) continue;
            p.total++;
            if (st == 'In League') {
                p.inLeague++;
                p.screening++;
            } else if (st == 'Interview Requested') {
                p.interviewRequested++;
                p.interview1++;
            } else if (st == 'Interview Confirmed') {
                p.interviewConfirmed++;
                p.interview2++;
            } else if (st == 'Interview Rejected') {
                p.interviewRejected++;
                p.rejected++;
            } else if (st == 'Reschedule Requested') {
                p.rescheduleRequested++;
                p.offered++;
            } else if (st == 'Candidate Shortlisted') {
                p.candidateShortlisted++;
                p.shortlisted++;
            } else if (st == 'Candidate Rejected') {
                p.candidateRejected++;
                p.rejected++;
            }
        }
        return p;
    }

    /** Query skills via Campaign_Skill__c junction */
    private static Map<Id, List<String>> getSkillsByCampaign(Set<Id> cIds) {
        Map<Id, List<String>> result = new Map<Id, List<String>>();
        for (R_ATS__Campaign_Skills__c cs : [
            SELECT 	R_ATS__Campaign__c, R_ATS__Skill__r.Name
            FROM R_ATS__Campaign_Skills__c
            WHERE R_ATS__Campaign__c IN :cIds
            ORDER BY R_ATS__Skill__r.Name
        ]) {
            if (!result.containsKey(cs.R_ATS__Campaign__c)) {
                result.put(cs.R_ATS__Campaign__c, new List<String>());
            }
            result.get(cs.R_ATS__Campaign__c).add(cs.R_ATS__Skill__r.Name);
        }
        return result;
    }

    /** Link Skill Library records via junction */
    private static String skillsToText(List<String> skills) {
        if (skills == null || skills.isEmpty()) return null;
        List<String> cleaned = new List<String>();
        for (String skill : skills) {
            if (String.isNotBlank(skill)) cleaned.add(skill.trim());
        }
        return cleaned.isEmpty() ? null : String.join(cleaned, ', ');
    }

    private static String getSeniorityValue(JobListingDTO.JobCreateRequest req) {
        if (req == null) return null;
        return String.isNotBlank(req.seniority) ? req.seniority : req.seniorityLevel;
    }

    private static String normalizeSeniority(String value) {
        String lower = String.isBlank(value) ? '' : value.trim().toLowerCase();
        if (lower == 'junior') return 'Junior';
        if (lower == 'mid') return 'Mid';
        if (lower == 'senior') return 'Senior';
        if (lower == 'lead') return 'Lead';
        if (lower == 'executive') return 'Executive';
        return null;
    }

    private static List<String> parseSkillText(String skillsText) {
        List<String> skills = new List<String>();
        if (String.isBlank(skillsText)) return skills;
        for (String skill : skillsText.split(',')) {
            if (String.isNotBlank(skill)) skills.add(skill.trim());
        }
        return skills;
    }

    private static void linkSkillCodes(Id cId, List<String> names) {
        List<R_ATS__Topic_Library__c> libs = [
            SELECT Id FROM R_ATS__Topic_Library__c WHERE Name IN :names
        ];
        List<R_ATS__Campaign_Skills__c> junctions = new List<R_ATS__Campaign_Skills__c>();
        for (R_ATS__Topic_Library__c sl : libs) {
            junctions.add(new R_ATS__Campaign_Skills__c(
                R_ATS__Campaign__c = cId, R_ATS__Skill__c = sl.Id
            ));
        }
        if (!junctions.isEmpty()) insert junctions;
    }

    /** Create linked Opportunity (reverse of OpportunityTrigger) */
    private static void createLinkedOpportunity(
        Id campaignId, JobListingDTO.JobCreateRequest req
    ) {
        String oppRtName;
        if (req.type == 'Permanent') oppRtName = 'Permanent_Placement';
        else if (req.type == 'Contract') oppRtName = 'Contract_Placement';
        else oppRtName = 'Temporary';

        Id oppRtId = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(oppRtName).getRecordTypeId();

        Opportunity opp = new Opportunity(
            Name = req.title,
            RecordTypeId = oppRtId,
            AccountId = req.accountId,
            CloseDate = Date.today().addDays(90),
            StageName = 'Qualification',
            R_ATS__No_of_openings__c = req.openings != null ? String.valueOf(req.openings) : '1'
        );
        insert opp;

        update new Campaign(Id = campaignId, Opportunity__c = opp.Id);
        // CampaignTrigger syncs No_of_openings automatically
    }

    /** Check contacts with resumes in Document Library */
    private static Set<Id> getContactsWithResume(Set<Id> contactIds) {
        Set<Id> result = new Set<Id>();
        if (contactIds.isEmpty()) return result;
        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId FROM ContentDocumentLink
            WHERE LinkedEntityId IN :contactIds
              AND ContentDocument.FileType IN ('PDF','DOCX','DOC')
            LIMIT 1000
        ]) {
            result.add(cdl.LinkedEntityId);
        }
        return result;
    }

    /** Activity feed from Tasks */
    private static List<JobListingDTO.ActivityItem> getActivityFeed(Id cId) {
        List<JobListingDTO.ActivityItem> feed =
            new List<JobListingDTO.ActivityItem>();

        for (Task t : [
            SELECT Subject, CreatedDate, Owner.Name, Type
            FROM Task WHERE WhatId = :cId
            ORDER BY CreatedDate DESC LIMIT 20
        ]) {
            JobListingDTO.ActivityItem item = new JobListingDTO.ActivityItem();
            item.eventTime = t.CreatedDate;
            item.eventType = t.Type != null ? t.Type : 'task';
            item.description = t.Subject;
            item.performedBy = t.Owner.Name;
            feed.add(item);
        }
        return feed;
    }

    /** Generate next RATS-NNN reference */
    private static String generateJobReference() {
        AggregateResult[] mx = [
            SELECT MAX(	R_ATS__Job_Reference_Number__c) maxRef
            FROM Campaign
            WHERE R_ATS__Job_Reference_Number__c LIKE 'RATS-%'
        ];
        Integer next = 100;
        if (mx[0].get('maxRef') != null) {
            String numPart = ((String)mx[0].get('maxRef')).substringAfter('RATS-');
            if (numPart.isNumeric()) next = Integer.valueOf(numPart) + 1;
        }
        return 'RATS-' + String.valueOf(next);
    }

    private static String buildLocationString(String city, String state) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(city)) parts.add(city);
        if (String.isNotBlank(state)) parts.add(state);
        return String.join(parts, ', ');
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
}
