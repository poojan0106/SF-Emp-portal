/**
 * TalentPoolController
 * Manages talent pool operations for employer portal
 */
public with sharing class TalentPoolController {
    
    @AuraEnabled(cacheable=true)
    public static List<TalentPoolWrapper> getEmployerTalentPools(Id accountId) {
        
        System.debug('DEBUG 1: Entered getEmployerTalentPools | accountId = ' + accountId);
        
        List<Campaign> pools = [
            SELECT Id, Name, NumberOfContacts, 	Quality_Score__c, 
                   	Last_Activity__c, CreatedDate
            FROM Campaign
            WHERE RecordType.DeveloperName = 'Talent_Pool'
            AND Employer__c = :accountId
            AND IsActive = true
            ORDER BY NumberOfContacts DESC
        ];
        
        System.debug('DEBUG 2: Total Pools Found = ' + pools.size());
        
        // Get new this week counts
        Date weekAgo = Date.today().addDays(-7);
        System.debug('DEBUG 3: WeekAgo Date = ' + weekAgo);
        Map<Id, Integer> newCounts = new Map<Id, Integer>();
        
        for (AggregateResult ar : [
            SELECT CampaignId, COUNT(Id) cnt
            FROM CampaignMember
            WHERE CampaignId IN :pools
            AND Interest_Date__c >= :weekAgo
            GROUP BY CampaignId
        ]) {
            newCounts.put((Id) ar.get('CampaignId'), (Integer) ar.get('cnt'));
        }
        
         System.debug('DEBUG 4: New This Week Map = ' + newCounts);
        
        List<TalentPoolWrapper> wrappers = new List<TalentPoolWrapper>();
        for (Campaign pool : pools) {
            System.debug('DEBUG 5: Processing Pool = ' + pool.Name);
            TalentPoolWrapper wrapper = new TalentPoolWrapper();
            wrapper.poolId = pool.Id;
            wrapper.name = pool.Name;
            wrapper.totalCandidates = pool.NumberOfContacts != null ? pool.NumberOfContacts : 0;
            wrapper.newThisWeek = newCounts.containsKey(pool.Id) ? newCounts.get(pool.Id) : 0;
            wrapper.qualityScore = pool.Quality_Score__c;
            wrapper.lastActivity = pool.Last_Activity__c;
            wrappers.add(wrapper);
        }
        
        System.debug('DEBUG 6: Returning Wrapper Count = ' + wrappers.size());
        
        return wrappers;
    }
    
    @AuraEnabled
    public static CandidateListResult getPoolCandidates(Id poolId, CandidateFilter filters, Integer pageNumber, Integer pageSize) {
        
            System.debug('DEBUG 10: Entered getPoolCandidates');
            System.debug('DEBUG 11: poolId=' + poolId + ' pageNumber=' + pageNumber + ' pageSize=' + pageSize);
            System.debug('DEBUG 12: Filters=' + JSON.serialize(filters));
        
        // Get subscription tier
        List<Campaign> poolRows = [SELECT Employer__c FROM Campaign WHERE Id = :poolId LIMIT 1];
        if (poolRows.isEmpty()) {
            CandidateListResult emptyResult = new CandidateListResult();
            emptyResult.candidates = new List<CandidateWrapper>();
            emptyResult.totalCount = 0;
            emptyResult.pageNumber = pageNumber;
            emptyResult.pageSize = pageSize;
            emptyResult.totalPages = 0;
            return emptyResult;
        }
        Campaign pool = poolRows[0];
        String tier = SubscriptionService.getSubscriptionTier(pool.Employer__c);
         System.debug('DEBUG 13: Subscription Tier = ' + tier);
        
        // Build query
        String query = 'SELECT Id, ContactId, Contact.FirstName, Contact.LastName, Contact.Email, ' +
            'Contact.Phone, Contact.MailingCity, Contact.R_ATS__Skills__c, Contact.Job_Role__c, Contact.Years_Experience__c, ' +
            'AI_CV_Score__c, AI_CV_Tier__c, AI_CV_Score_Explanation__c, Combined_Score__c, Questionnaire_Score__c, ' +
            'Sentiment_Tags__c, Interest_Date__c, Full_Profile_Unlocked__c, Status, Swipe_Event__c, ' +
            'Identity_Reveal_Status__c, Identity_Reveal_Requested_Date__c, Identity_Reveal_Responded_Date__c ' +
            'FROM CampaignMember WHERE CampaignId = :poolId AND ( Swipe_Event__c != NULL OR Created_From_Candidate_Portal__c = true OR Swipe_Event__c !=\'\' )';
        
        // Apply filters
        if (filters != null) {
            if (String.isNotBlank(filters.location)) {
                query += ' AND Contact.MailingCity LIKE \'%' + String.escapeSingleQuotes(filters.location) + '%\'';
            }
            if (filters.minExperience != null) {
                query += ' AND Contact.Years_Experience__c >= ' + filters.minExperience;
            }
            if (filters.maxExperience != null) {
                query += ' AND Contact.Years_Experience__c <= ' + filters.maxExperience;
            }
        }
        
        query += ' ORDER BY Combined_Score__c DESC NULLS LAST, AI_CV_Score__c DESC NULLS LAST';
        
        System.debug('DEBUG 14: Final Query Before Count = ' + query);
        
        // Get total count - ✅ FIX: Extract WHERE clause properly
        String whereClause = query.substringAfter('FROM CampaignMember').substringBefore('ORDER BY');
        Integer totalCount = Database.countQuery('SELECT COUNT() FROM CampaignMember ' + whereClause);
        
        System.debug('DEBUG 15: Total Count = ' + totalCount);
        
        // Apply pagination
        Integer offset = (pageNumber - 1) * pageSize;
        query += ' LIMIT ' + pageSize + ' OFFSET ' + offset;
        
        System.debug('DEBUG 16: Final Query With Pagination = ' + query);
        
        List<CampaignMember> members = Database.query(query);
        System.debug('DEBUG 17: Members Retrieved = ' + members.size());
        
        List<CandidateWrapper> candidates = new List<CandidateWrapper>();
        Integer index = offset;
        for (CampaignMember member : members) {
            candidates.add(new CandidateWrapper(member, tier, index++));
        }
        
        CandidateListResult result = new CandidateListResult();
        result.candidates = candidates;
        result.totalCount = totalCount;
        result.pageNumber = pageNumber;
        result.pageSize = pageSize;
        result.totalPages = (Integer) Math.ceil((Decimal) totalCount / pageSize);
        
        System.debug('DEBUG 19: Total Pages = ' + result.totalPages);
        
        return result;
    }
    
    @AuraEnabled
    public static CandidateWrapper unlockCandidateProfile(Id campaignMemberId, Id accountId) {
        
        System.debug('DEBUG 20: Entered unlockCandidateProfile');
   		System.debug('DEBUG 21: campaignMemberId=' + campaignMemberId + ' accountId=' + accountId);
        
        // Validate subscription
        SubscriptionService.validateFeatureAccess(accountId, 'Profile_Unlock');
        
        CampaignMember member = [
            SELECT Id, ContactId, Contact.FirstName, Contact.LastName, Contact.Email,
                   Contact.Phone, Contact.MailingCity,Contact.Job_Role__c, Contact.R_ATS__Skills__c, Contact.Years_Experience__c,
                   AI_CV_Score__c, AI_CV_Tier__c, AI_CV_Score_Explanation__c, Combined_Score__c, Questionnaire_Score__c,
                   Sentiment_Tags__c, Full_Profile_Unlocked__c,Interest_Date__c,
                   Identity_Reveal_Status__c, Identity_Reveal_Requested_Date__c, Identity_Reveal_Responded_Date__c
            FROM CampaignMember
            WHERE Id = :campaignMemberId
        ];
        
        System.debug('DEBUG 22: Member Before Unlock = ' + JSON.serialize(member));
        
        // Update member
        member.Full_Profile_Unlocked__c = true;
        member.Unlocked_Date__c = DateTime.now();
        member.Unlocked_By__c = getCurrentUserId();
        update member;
        
        System.debug('DEBUG 23: Member Successfully Updated');
        
        // Track usage
        SubscriptionService.trackFeatureUsage(accountId, 'Profile_Unlock');
        
        return new CandidateWrapper(member, 'Professional', 0);
    }

    @AuraEnabled
    public static CandidateWrapper requestIdentityReveal(Id campaignMemberId, Id accountId) {
        SubscriptionService.validateFeatureAccess(accountId, 'Profile_Unlock');

        List<CampaignMember> members = [
            SELECT Id, ContactId, Contact.FirstName, Contact.LastName, Contact.Email,
                   Contact.Phone, Contact.MailingCity, Contact.Job_Role__c, Contact.R_ATS__Skills__c,
                   Contact.Years_Experience__c, AI_CV_Score__c, AI_CV_Tier__c,
                   AI_CV_Score_Explanation__c, Combined_Score__c, Questionnaire_Score__c, Sentiment_Tags__c,
                   Full_Profile_Unlocked__c, Interest_Date__c, Status, Swipe_Event__c,
                   Identity_Reveal_Status__c, Identity_Reveal_Requested_Date__c,
                   Identity_Reveal_Responded_Date__c, Campaign.Employer__c, Campaign.Employer__r.Name
            FROM CampaignMember
            WHERE Id = :campaignMemberId
            AND Campaign.Employer__c = :accountId
            LIMIT 1
        ];

        if (members.isEmpty()) {
            throw new AuraHandledException('Candidate is not in this employer talent pool');
        }

        CampaignMember member = members[0];

        if (member.Identity_Reveal_Status__c != 'Approved') {
            member.Identity_Reveal_Status__c = 'Requested';
            member.Identity_Reveal_Requested_Date__c = DateTime.now();
            member.Full_Profile_Unlocked__c = false;
            member.Unlocked_Date__c = null;
            update member;

            try {
                ensureRevealRequest(member);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Unable to create reveal request: ' + e.getMessage());
            }

            try {
                NotificationService.notify(
                    member.ContactId,
                    'Message',
                    'Identity reveal request from ' + member.Campaign.Employer__r.Name,
                    member.Campaign.Employer__r.Name + ' wants to view your identity. Approve or decline this request.',
                    '/notifications?revealRequestId=' + member.Id,
                    'High'
                );
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Unable to create identity reveal notification: ' + e.getMessage());
            }

            try {
                notifyCandidateRevealRequest(member);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Unable to send identity reveal request email: ' + e.getMessage());
            }
        }

        SubscriptionService.trackFeatureUsage(accountId, 'Profile_Unlock');
        return new CandidateWrapper(member, SubscriptionService.getSubscriptionTier(accountId), 0);
    }

    @AuraEnabled
    public static CandidateWrapper respondIdentityReveal(Id campaignMemberId, Id candidateId, Boolean approved) {
        List<CampaignMember> members = [
            SELECT Id, ContactId, Contact.FirstName, Contact.LastName, Contact.Email,
                   Contact.Phone, Contact.MailingCity, Contact.Job_Role__c, Contact.R_ATS__Skills__c,
                   Contact.Years_Experience__c, AI_CV_Score__c, AI_CV_Tier__c,
                   AI_CV_Score_Explanation__c, Combined_Score__c, Questionnaire_Score__c, Sentiment_Tags__c,
                   Full_Profile_Unlocked__c, Interest_Date__c, Status, Swipe_Event__c,
                   Identity_Reveal_Status__c, Identity_Reveal_Requested_Date__c,
                   Identity_Reveal_Responded_Date__c, Campaign.Employer__c, Campaign.Employer__r.Name
            FROM CampaignMember
            WHERE Id = :campaignMemberId
            AND ContactId = :candidateId
            LIMIT 1
        ];

        if (members.isEmpty()) {
            throw new AuraHandledException('Identity reveal request does not belong to this candidate');
        }

        CampaignMember member = members[0];

        member.Identity_Reveal_Status__c = approved == true ? 'Approved' : 'Rejected';
        member.Identity_Reveal_Responded_Date__c = DateTime.now();
        if (approved == true) {
            member.Full_Profile_Unlocked__c = true;
            member.Unlocked_Date__c = DateTime.now();
        } else {
            member.Full_Profile_Unlocked__c = false;
            member.Unlocked_Date__c = null;
        }
        update member;

        syncRevealRequestDecision(member.Id, approved == true);
        try {
            notifyEmployerRevealDecision(member, approved == true);
            notifyCandidateRevealDecision(member, approved == true);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Unable to send identity reveal decision email: ' + e.getMessage());
        }
        upsertProtectionMetric(member.ContactId);

        return new CandidateWrapper(member, 'Free', 0);
    }

    private static void ensureRevealRequest(CampaignMember member) {
        String campaignMemberId = String.valueOf(member.Id);
        List<Reveal_Request__c> existing = [
            SELECT Id
            FROM Reveal_Request__c
            WHERE CampaignMember_Id__c = :campaignMemberId
            AND Status__c = 'Pending'
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            return;
        }

        insert new Reveal_Request__c(
            Employer__c = member.Campaign.Employer__c,
            Candidate__c = member.ContactId,
            CampaignMember_Id__c = campaignMemberId,
            Request_Date__c = DateTime.now(),
            Status__c = 'Pending',
            Reason__c = member.Campaign.Employer__r.Name + ' wants to know who you are to schedule an interview.'
        );
    }

    private static void syncRevealRequestDecision(Id campaignMemberId, Boolean approved) {
        String campaignMemberKey = String.valueOf(campaignMemberId);
        List<Reveal_Request__c> requests = [
            SELECT Id, Status__c, Decision_Date__c
            FROM Reveal_Request__c
            WHERE CampaignMember_Id__c = :campaignMemberKey
            AND Status__c = 'Pending'
            ORDER BY Request_Date__c DESC
            LIMIT 1
        ];

        if (requests.isEmpty()) {
            return;
        }

        Reveal_Request__c request = requests[0];
        request.Status__c = approved ? 'Approved' : 'Declined';
        request.Decision_Date__c = DateTime.now();
        update request;
    }

    private static void notifyEmployerRevealDecision(CampaignMember member, Boolean approved) {
        if (member.Campaign == null || member.Campaign.Employer__c == null) return;
        List<Contact> employerUsers = [
            SELECT Email, FirstName
            FROM Contact
            WHERE AccountId = :member.Campaign.Employer__c
            AND Email != null
            LIMIT 5
        ];
        if (employerUsers.isEmpty()) return;

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Contact employerUser : employerUsers) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ employerUser.Email });
            email.setSubject(approved ? 'Identity reveal approved' : 'Identity reveal declined');
            email.setPlainTextBody(
                approved
                    ? 'Candidate approved your identity reveal request. You can continue interview scheduling.'
                    : 'Candidate declined your identity reveal request. Their identity remains masked.'
            );
            emails.add(email);
        }
        Messaging.sendEmail(emails, false);
    }

    private static void notifyCandidateRevealRequest(CampaignMember member) {
        if (member.Contact == null || String.isBlank(member.Contact.Email)) return;
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ member.Contact.Email });
        email.setSubject('Identity reveal request from ' + member.Campaign.Employer__r.Name);
        email.setPlainTextBody(
            member.Campaign.Employer__r.Name +
            ' wants to view your identity. Open your candidate dashboard to approve or decline this request.'
        );
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email }, false);
    }

    private static void notifyCandidateRevealDecision(CampaignMember member, Boolean approved) {
        if (member.Contact == null || String.isBlank(member.Contact.Email)) return;
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ member.Contact.Email });
        email.setSubject(approved ? 'Identity reveal approved' : 'Identity reveal declined');
        email.setPlainTextBody(
            approved
                ? 'You approved the identity reveal request from ' + member.Campaign.Employer__r.Name + '.'
                : 'You declined the identity reveal request from ' + member.Campaign.Employer__r.Name + '. Your identity remains masked.'
        );
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email }, false);
    }

    private static void upsertProtectionMetric(Id candidateId) {
        List<CampaignMember> members = [
            SELECT Id, Identity_Reveal_Status__c, Full_Profile_Unlocked__c
            FROM CampaignMember
            WHERE ContactId = :candidateId
            AND Campaign.Is_Talent_Pool__c = true
        ];
        Integer requests = 0;
        Integer approved = 0;
        Integer declined = 0;
        Integer masked = 0;
        for (CampaignMember member : members) {
            if (member.Identity_Reveal_Status__c != null) requests++;
            if (member.Identity_Reveal_Status__c == 'Approved') approved++;
            if (member.Identity_Reveal_Status__c == 'Rejected') declined++;
            if (member.Full_Profile_Unlocked__c != true) masked++;
        }

        List<Protection_Metric__c> existing = [
            SELECT Id
            FROM Protection_Metric__c
            WHERE Candidate__c = :candidateId
            LIMIT 1
        ];
        Protection_Metric__c metric = existing.isEmpty()
            ? new Protection_Metric__c(Candidate__c = candidateId)
            : existing[0];
        metric.Masked_Profiles_Shared__c = masked;
        metric.Reveal_Requests_Received__c = requests;
        metric.Reveals_Approved__c = approved;
        metric.Reveals_Declined__c = declined;
        metric.Last_Updated__c = DateTime.now();
        upsert metric;
    }
    
    @AuraEnabled
    public static void requestInterview(Id campaignMemberId, Id accountId, String message) {
        requestInterviewWithLink(campaignMemberId, accountId, message, null);
    }

    @AuraEnabled
    public static void requestInterviewWithLink(Id campaignMemberId, Id accountId, String message, String interviewLink) {
        requestInterviewWithDetails(campaignMemberId, accountId, message, interviewLink, null, null);
    }

    @AuraEnabled
    public static void requestInterviewWithDetails(Id campaignMemberId, Id accountId, String message, String interviewLink, String scheduledStart, String scheduledEnd) {
        // Validate subscription
        SubscriptionService.validateFeatureAccess(accountId, 'Interview_Request');
        
        CampaignMember member = [
            SELECT Id, ContactId, Contact.Email, Contact.FirstName, CampaignId, Campaign.Employer__c, Campaign.Employer__r.Name
            FROM CampaignMember WHERE Id = :campaignMemberId
        ];
        if (member.Campaign == null || member.Campaign.Employer__c != accountId) {
            throw new AuraHandledException('Campaign member does not belong to this employer');
        }

        DateTime interviewStart = parseInterviewDateTime(scheduledStart);
        if (interviewStart == null) {
            interviewStart = DateTime.newInstance(Date.today().addDays(3), Time.newInstance(9, 0, 0, 0));
        }
        DateTime interviewEnd = parseInterviewDateTime(scheduledEnd);
        if (interviewEnd == null || interviewEnd <= interviewStart) {
            interviewEnd = interviewStart.addMinutes(30);
        }

        List<Interview__c> duplicateInterviews = [
            SELECT Id
            FROM Interview__c
            WHERE Candidate__c = :member.ContactId
            AND Interview_Date__c = :interviewStart
            AND Interview_Status__c IN ('Scheduled', 'Confirmed', 'Reschedule Requested')
            LIMIT 1
        ];
        if (!duplicateInterviews.isEmpty()) {
            throw new AuraHandledException('Interview already exists for this candidate at the selected date/time');
        }
        
        // Update member status
        member.Interview_Requested__c = true;
        member.Interview_Request_Date__c = DateTime.now();
        ensureInterviewCampaignMemberStatuses(new Set<Id>{ member.CampaignId });
        member.Status = 'Interview Requested';
        update member;

        Interview__c interview = new Interview__c(
            Candidate__c = member.ContactId,
            Interview_Date__c = interviewStart,
            Interview_End_Date__c = interviewEnd,
            Interview_Type__c = 'Video Call',
            Interview_Status__c = 'Scheduled',
            Interview_Link__c = interviewLink,
            Interviewer__c = UserInfo.getUserId(),
            Interviewer_Notes__c = message,
            Next_Steps__c = 'Candidate should review and confirm interview invitation.'
        );
        insert interview;

        try {
            insert new Rescue_Opportunity__c(
                Account__c = accountId,
                Contact__c = member.ContactId,
                CampaignMember_Id__c = member.Id,
                Interview__c = interview.Id,
                Interview_Date__c = interviewStart,
                Interview_End_Date__c = interviewEnd,
                Interview_Type__c = 'Video',
                Status__c = 'Scheduled',
                Blakeney_Prep_Notes__c = message
            );
        } catch (Exception rescueError) {
            System.debug(LoggingLevel.ERROR, 'Unable to create Rescue_Opportunity__c for interview ' + interview.Id + ': ' + rescueError.getMessage());
        }
        
        // Send notification email to candidate
        String candidateMessage = message;
        if (String.isNotBlank(interviewLink)) {
            candidateMessage = String.isBlank(candidateMessage)
                ? 'Interview Link: ' + interviewLink
                : candidateMessage + '\n\nInterview Link: ' + interviewLink;
        }

        EmailService.sendInterviewRequest(
            member.Contact.Email,
            member.Contact.FirstName,
            member.Campaign.Employer__r.Name,
            candidateMessage
        );

        NotificationService.notifyInterviewInvitation(
            member.ContactId,
            member.Campaign.Employer__r.Name,
            null
        );
    }

    private static void ensureInterviewCampaignMemberStatuses(Set<Id> campaignIds) {
        if (campaignIds == null || campaignIds.isEmpty()) return;
        Set<String> needed = new Set<String>{
            'In League',
            'Interview Requested',
            'Interview Confirmed',
            'Interview Rejected',
            'Reschedule Requested',
            'Candidate Shortlisted',
            'Candidate Rejected'
        };
        Set<String> existingKeys = new Set<String>();
        for (CampaignMemberStatus statusRecord : [
            SELECT CampaignId, Label
            FROM CampaignMemberStatus
            WHERE CampaignId IN :campaignIds
            AND Label IN :needed
        ]) {
            existingKeys.add(String.valueOf(statusRecord.CampaignId) + '|' + statusRecord.Label);
        }
        List<CampaignMemberStatus> toInsert = new List<CampaignMemberStatus>();
        Map<String, Integer> sortOrderByStatus = new Map<String, Integer>{
            'In League' => 20,
            'Interview Requested' => 50,
            'Interview Confirmed' => 60,
            'Interview Rejected' => 65,
            'Reschedule Requested' => 70,
            'Candidate Shortlisted' => 90,
            'Candidate Rejected' => 95
        };
        for (Id campaignId : campaignIds) {
            for (String label : needed) {
                String key = String.valueOf(campaignId) + '|' + label;
                if (!existingKeys.contains(key)) {
                    toInsert.add(new CampaignMemberStatus(
                        CampaignId = campaignId,
                        Label = label,
                        HasResponded = true,
                        IsDefault = false,
                        SortOrder = sortOrderByStatus.get(label)
                    ));
                }
            }
        }
        if (!toInsert.isEmpty()) Database.insert(toInsert, false);
    }

    private static DateTime parseInterviewDateTime(String value) {
        if (String.isBlank(value)) return null;
        try {
            return (DateTime) JSON.deserialize('"' + value + '"', DateTime.class);
        } catch (Exception e) {
            try {
                return DateTime.valueOf(value.replace('T', ' ').replace('Z', ''));
            } catch (Exception ignored) {
                return null;
            }
        }
    }
    
    @AuraEnabled
    public static PoolMetrics getPoolMetrics(Id poolId) {
        System.debug('DEBUG 40: Entered getPoolMetrics');
    	System.debug('DEBUG 41: poolId = ' + poolId);
        
        List<Campaign> poolRows = [
            SELECT Id, NumberOfContacts, Quality_Score__c
            FROM Campaign WHERE Id = :poolId
            LIMIT 1
        ];
        if (poolRows.isEmpty()) {
            PoolMetrics emptyMetrics = new PoolMetrics();
            emptyMetrics.total = 0;
            emptyMetrics.candidates = 0;
            emptyMetrics.newThisWeek = 0;
            emptyMetrics.avgExperience = 0;
            emptyMetrics.topSkills = new List<String>();
            emptyMetrics.jobRoles = new List<String>();
            emptyMetrics.qualityScore = 0;
            return emptyMetrics;
        }
        Campaign pool = poolRows[0];
        
            System.debug('DEBUG 42: Pool Retrieved | Id=' + pool.Id + 
        ' | NumberOfContacts=' + pool.NumberOfContacts + 
        ' | Quality_Score__c=' + pool.Quality_Score__c
   		 );
        
        List<AggregateResult> results = [
            SELECT AVG(AI_CV_Score__c) avgScore, AVG(Contact.Years_Experience__c) avgExp
            FROM CampaignMember
            WHERE CampaignId = :poolId
        ];
        
        System.debug('DEBUG 43: Aggregate Results Size = ' + results.size());
        
        Date weekAgo = Date.today().addDays(-7);
        System.debug('DEBUG 44: weekAgo Date = ' + weekAgo);
        
        Integer newThisWeek = [
            SELECT COUNT() FROM CampaignMember
            WHERE CampaignId = :poolId AND Interest_Date__c >= :weekAgo
        ];
        
        System.debug('DEBUG 45: newThisWeek Count = ' + newThisWeek);
        
        Integer count = [SELECT COUNT() FROM CampaignMember 
                WHERE CampaignId = :poolId ];
        
        // ✅ Query Job Roles
        List<CampaignMember> campaignMembers = [
            SELECT Contact.Job_Role__c 
            FROM CampaignMember 
            WHERE CampaignId = :poolId
        ];
        
        PoolMetrics metrics = new PoolMetrics();
        System.debug('DEBUG 2: pool.NumberOfContacts = ' + pool.NumberOfContacts);
        //metrics.total = pool.NumberOfContacts != null ? pool.NumberOfContacts : 0;
        metrics.total = count;
        System.debug('DEBUG 3: metrics.total = ' + metrics.total);
        metrics.candidates = metrics.total;  // Set both
        System.debug('DEBUG 4: metrics.candidates = ' + metrics.candidates);
        metrics.newThisWeek = newThisWeek;
        metrics.qualityScore = pool.Quality_Score__c;
        metrics.topSkills = getTopSkillsForPool(poolId);
        // ✅ Populate Job Roles
        metrics.jobRoles = new List<String>();
        for (CampaignMember member : campaignMembers) {
            if (String.isNotBlank(member.Contact.Job_Role__c)) {
                metrics.jobRoles.add(member.Contact.Job_Role__c);
            }
        }
    
    System.debug('DEBUG 49: Job Roles = ' + metrics.jobRoles);
        
        if (!results.isEmpty()) {
            metrics.avgMatchScore = (Decimal) results[0].get('avgScore');
            metrics.avgExperience = (Decimal) results[0].get('avgExp');
            System.debug('DEBUG 46: AvgMatchScore=' + metrics.avgMatchScore +
            ' | AvgExperience=' + metrics.avgExperience
        );
        }
        
        System.debug(LoggingLevel.INFO, 
        'DEBUG 47: Final Metrics Object = ' + JSON.serialize(metrics)
    	);
        
        return metrics;
    }

    @AuraEnabled(cacheable=true)
    public static ScoringConfigurationWrapper getScoringConfiguration() {
        ScoringConfigurationWrapper config = new ScoringConfigurationWrapper();

        if (Schema.getGlobalDescribe().containsKey('Scoring_Configuration__mdt')) {
            try {
                List<SObject> rows = Database.query(
                    'SELECT Skills_Weight_Total__c, Skills_Weight__c, Skills_Weight_Nice_To_Have__c, ' +
                    'Experience_Weight__c, Location_Weight__c, Salary_Weight__c, CV_Score_Weight__c, ' +
                    'Questionnaire_Score_Weight__c, Questionnaire_Threshold__c, Potential_Match_Min__c, ' +
                    'Review_Required_Min__c, Poor_Match_Max__c ' +
                    'FROM Scoring_Configuration__mdt WHERE DeveloperName = \'Default\' LIMIT 1'
                );

                if (!rows.isEmpty()) {
                    SObject row = rows[0];
                    config.skillsWeightTotal = decimalOrDefault(row, 'Skills_Weight_Total__c', config.skillsWeightTotal);
                    config.skillsWeight = decimalOrDefault(row, 'Skills_Weight__c', config.skillsWeight);
                    config.skillsNiceToHaveWeight = decimalOrDefault(row, 'Skills_Weight_Nice_To_Have__c', config.skillsNiceToHaveWeight);
                    config.experienceWeight = decimalOrDefault(row, 'Experience_Weight__c', config.experienceWeight);
                    config.locationWeight = decimalOrDefault(row, 'Location_Weight__c', config.locationWeight);
                    config.salaryWeight = decimalOrDefault(row, 'Salary_Weight__c', config.salaryWeight);
                    config.cvScoreWeight = decimalOrDefault(row, 'CV_Score_Weight__c', config.cvScoreWeight);
                    config.questionnaireScoreWeight = decimalOrDefault(row, 'Questionnaire_Score_Weight__c', config.questionnaireScoreWeight);
                    config.questionnaireThreshold = decimalOrDefault(row, 'Questionnaire_Threshold__c', config.questionnaireThreshold);
                    config.potentialMatchMin = decimalOrDefault(row, 'Potential_Match_Min__c', config.potentialMatchMin);
                    config.reviewRequiredMin = decimalOrDefault(row, 'Review_Required_Min__c', config.reviewRequiredMin);
                    config.poorMatchMax = decimalOrDefault(row, 'Poor_Match_Max__c', config.poorMatchMax);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Scoring config response fallback used: ' + e.getMessage());
            }
        }

        config.scoreBuckets = buildScoreBuckets(config);
        config.tiers = buildTierOptions(config);
        return config;
    }

    private static Decimal decimalOrDefault(SObject row, String fieldName, Decimal fallbackValue) {
        Object rawValue = row.get(fieldName);
        return rawValue == null ? fallbackValue : (Decimal) rawValue;
    }

    private static List<ScoringOptionWrapper> buildScoreBuckets(ScoringConfigurationWrapper config) {
        Integer potentialMin = config.potentialMatchMin.intValue();
        Integer reviewMin = config.reviewRequiredMin.intValue();
        Integer poorMax = config.poorMatchMax.intValue();

        return new List<ScoringOptionWrapper>{
            new ScoringOptionWrapper('potential', String.valueOf(potentialMin) + '+', potentialMin, 100),
            new ScoringOptionWrapper('review', String.valueOf(reviewMin) + '-' + String.valueOf(potentialMin - 1), reviewMin, potentialMin - 1),
            new ScoringOptionWrapper('poor', '0-' + String.valueOf(poorMax), 0, poorMax)
        };
    }

    private static List<ScoringOptionWrapper> buildTierOptions(ScoringConfigurationWrapper config) {
        Integer potentialMin = config.potentialMatchMin.intValue();
        Integer reviewMin = config.reviewRequiredMin.intValue();
        Integer poorMax = config.poorMatchMax.intValue();

        return new List<ScoringOptionWrapper>{
            new ScoringOptionWrapper('potential match', 'Potential Match', potentialMin, 100),
            new ScoringOptionWrapper('review required', 'Review Required', reviewMin, potentialMin - 1),
            new ScoringOptionWrapper('poor match', 'Poor Match', 0, poorMax)
        };
    }
    
        
    /**
     * ⭐ NEW METHOD: Get top skills for pool from R_ATS__Skills__c field
     */
    private static List<String> getTopSkillsForPool(Id poolId) {
        System.debug('=== getTopSkillsForPool START ===');
        
        Map<String, String> uniqueSkillsMap = new Map<String, String>();
        
        try {
            List<CampaignMember> members = [
                SELECT Contact.R_ATS__Skills__c
                FROM CampaignMember
                WHERE CampaignId = :poolId 
            ];
            
            for (CampaignMember member : members) {
                if (member.Contact != null && String.isNotBlank(member.Contact.R_ATS__Skills__c)) {
                    System.debug('Skills : ' + member.Contact.R_ATS__Skills__c);
                    
                    List<String> parsedSkills = parseSkillsList(member.Contact.R_ATS__Skills__c);
                    
                    for (String skill : parsedSkills) {
                        if (String.isNotBlank(skill)) {
                            String trimmedSkill = skill.trim();
                            String key = trimmedSkill.toLowerCase();
                            
                            // Only add if not already present (case-insensitive)
                            if (!uniqueSkillsMap.containsKey(key)) {
                                uniqueSkillsMap.put(key, trimmedSkill);
                            }
                        }
                    }
                }
            }
            
            return new List<String>(uniqueSkillsMap.values());
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in getTopSkillsForPool: ' + e.getMessage());
            return new List<String>();
        }
    }  
    /**
     * Parse skills from string
     */
    private static List<String> parseSkillsList(String skillsJson) {
        List<String> skills = new List<String>();
        
        if (String.isBlank(skillsJson)) return skills;
        
        try {
            List<Object> parsed = (List<Object>) JSON.deserializeUntyped(skillsJson);
            for (Object skill : parsed) {
                String skillStr = String.valueOf(skill).trim();
                if (String.isNotBlank(skillStr)) {
                    skills.add(skillStr);
                }
            }
        } catch (Exception e) {
            for (String skill : skillsJson.split(',')) {
                String skillTrimmed = skill.trim();
                if (String.isNotBlank(skillTrimmed)) {
                    skills.add(skillTrimmed);
                }
            }
        }
        
        return skills;
    }
    
    private static Id getCurrentUserId() {
        Id userId = UserInfo.getUserId();
        List<Contact> contacts = [SELECT Id FROM Contact WHERE User__c = :userId LIMIT 1];
        return contacts.isEmpty() ? null : contacts[0].Id;
    }
    
    // Wrapper classes
    public class TalentPoolWrapper {
        @AuraEnabled public Id poolId;
        @AuraEnabled public String name;
        @AuraEnabled public Integer totalCandidates;
        @AuraEnabled public Integer newThisWeek;
        @AuraEnabled public Decimal qualityScore;
        @AuraEnabled public Date lastActivity;
    }
    
    public class CandidateWrapper {
        @AuraEnabled public Id memberId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String displayId;
        @AuraEnabled public Integer matchScore;
        @AuraEnabled public Integer aiCvScore;
        @AuraEnabled public String aiCvTier;
        @AuraEnabled public String aiCvScoreExplanation;
        @AuraEnabled public Integer combinedScore;
        @AuraEnabled public Integer questionnaireScore;
        @AuraEnabled public List<String> skills;
        @AuraEnabled public Decimal experienceYears;
        @AuraEnabled public String location;
        @AuraEnabled public String sentimentTags;
        @AuraEnabled public Boolean isUnlocked;
        @AuraEnabled public DateTime interestDate;
        @AuraEnabled public String jobRole;
        @AuraEnabled public String revealStatus;
        @AuraEnabled public DateTime revealRequestedDate;
        @AuraEnabled public DateTime revealRespondedDate;
        // Full details (only if unlocked)
        @AuraEnabled public String fullName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        
        public CandidateWrapper(CampaignMember member, String tier, Integer index) {
            this.memberId = member.Id;
            this.contactId = member.ContactId;
            Decimal bestScore = member.Combined_Score__c != null
                ? member.Combined_Score__c
                : member.AI_CV_Score__c;
            this.matchScore = bestScore != null ? bestScore.intValue() : 0;
            this.aiCvScore = member.AI_CV_Score__c != null ? member.AI_CV_Score__c.intValue() : null;
            this.aiCvTier = member.AI_CV_Tier__c;
            this.aiCvScoreExplanation = member.AI_CV_Score_Explanation__c;
            this.combinedScore = member.Combined_Score__c != null ? member.Combined_Score__c.intValue() : null;
            this.questionnaireScore = member.Questionnaire_Score__c != null ? member.Questionnaire_Score__c.intValue() : null;
            this.sentimentTags = member.Sentiment_Tags__c;
            this.isUnlocked = member.Full_Profile_Unlocked__c == true
                && member.Identity_Reveal_Status__c == 'Approved';
            this.interestDate = member.Interest_Date__c;
            this.revealStatus = member.Identity_Reveal_Status__c;
            this.revealRequestedDate = member.Identity_Reveal_Requested_Date__c;
            this.revealRespondedDate = member.Identity_Reveal_Responded_Date__c;
            this.location = member.Contact.MailingCity;
            this.experienceYears = member.Contact.Years_Experience__c;
            this.jobRole = member.Contact.Job_Role__c;
            
            // Parse skills
            this.skills = new List<String>();
            if (String.isNotBlank(member.Contact.R_ATS__Skills__c)) {
                List<String> allSkills = member.Contact.R_ATS__Skills__c.split('[,;]+');
                // FIX 4: Apex List doesn't have subList() - use manual approach
                if (allSkills.size() > 5) {
                    for (Integer i = 0; i < 5; i++) {
                        this.skills.add(allSkills[i]);
                    }
                } else {
                    this.skills = allSkills;
                }
            }
            
            // Anonymized ID
            this.displayId = 'CANDIDATE ' + String.fromCharArray(new List<Integer>{ 65 + Math.mod(index, 26) });
            
            // Full details only if unlocked
            if (this.isUnlocked == true) {
                this.fullName = member.Contact.FirstName + ' ' + member.Contact.LastName;
                this.email = member.Contact.Email;
                this.phone = member.Contact.Phone;
            }
        }
    }
    
    public class CandidateFilter {
        @AuraEnabled public List<String> skills;
        @AuraEnabled public String location;
        @AuraEnabled public Integer minExperience;
        @AuraEnabled public Integer maxExperience;
        @AuraEnabled public String availability;
    }
    
    public class CandidateListResult {
        @AuraEnabled public List<CandidateWrapper> candidates;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer totalPages;
    }
    
    public class PoolMetrics {
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer candidates;
        @AuraEnabled public Integer newThisWeek;
        @AuraEnabled public Decimal qualityScore;
        @AuraEnabled public Decimal avgMatchScore;
        @AuraEnabled public Decimal avgExperience;
        @AuraEnabled public List<String> topSkills; 
        @AuraEnabled public List<String> jobRoles;
    }

    public class ScoringConfigurationWrapper {
        @AuraEnabled public Decimal skillsWeightTotal = 40;
        @AuraEnabled public Decimal skillsWeight = 30;
        @AuraEnabled public Decimal skillsNiceToHaveWeight = 10;
        @AuraEnabled public Decimal experienceWeight = 30;
        @AuraEnabled public Decimal locationWeight = 15;
        @AuraEnabled public Decimal salaryWeight = 15;
        @AuraEnabled public Decimal cvScoreWeight = 40;
        @AuraEnabled public Decimal questionnaireScoreWeight = 60;
        @AuraEnabled public Decimal questionnaireThreshold = 70;
        @AuraEnabled public Decimal potentialMatchMin = 70;
        @AuraEnabled public Decimal reviewRequiredMin = 40;
        @AuraEnabled public Decimal poorMatchMax = 39;
        @AuraEnabled public List<ScoringOptionWrapper> scoreBuckets;
        @AuraEnabled public List<ScoringOptionWrapper> tiers;
    }

    public class ScoringOptionWrapper {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public Integer min;
        @AuraEnabled public Integer max;

        public ScoringOptionWrapper(String value, String label, Integer min, Integer max) {
            this.value = value;
            this.label = label;
            this.min = min;
            this.max = max;
        }
    }
}