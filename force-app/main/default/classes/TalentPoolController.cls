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
        Campaign pool = [SELECT Employer__c FROM Campaign WHERE Id = :poolId];
        String tier = SubscriptionService.getSubscriptionTier(pool.Employer__c);
         System.debug('DEBUG 13: Subscription Tier = ' + tier);
        
        // Build query
        String query = 'SELECT Id, ContactId, Contact.FirstName, Contact.LastName, Contact.Email, ' +
            'Contact.Phone, Contact.MailingCity, Contact.R_ATS__Skills__c, Contact.Job_Role__c, Contact.Years_Experience__c, ' +
            'AI_Match_Score__c, Sentiment_Tags__c, Interest_Date__c, Full_Profile_Unlocked__c, Status ' +
            'FROM CampaignMember WHERE CampaignId = :poolId AND Status = \'Interested\'';
        
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
        
        query += ' ORDER BY AI_Match_Score__c DESC NULLS LAST';
        
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
                   AI_Match_Score__c, Sentiment_Tags__c, Full_Profile_Unlocked__c,Interest_Date__c
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
    public static void requestInterview(Id campaignMemberId, Id accountId, String message) {
        // Validate subscription
        SubscriptionService.validateFeatureAccess(accountId, 'Interview_Request');
        
        CampaignMember member = [
            SELECT Id, ContactId, Contact.Email, Contact.FirstName, CampaignId, Campaign.Employer__r.Name
            FROM CampaignMember WHERE Id = :campaignMemberId
        ];
        
        // Update member status
        member.Interview_Requested__c = true;
        member.Interview_Request_Date__c = DateTime.now();
        member.Status = 'Interview_Requested';
        update member;
        
        // Send notification email to candidate
        EmailService.sendInterviewRequest(
            member.Contact.Email,
            member.Contact.FirstName,
            member.Campaign.Employer__r.Name,
            message
        );

        NotificationService.notifyInterviewInvitation(
            member.ContactId,
            member.Campaign.Employer__r.Name,
            null
        );
    }
    
    @AuraEnabled
    public static PoolMetrics getPoolMetrics(Id poolId) {
        System.debug('DEBUG 40: Entered getPoolMetrics');
    	System.debug('DEBUG 41: poolId = ' + poolId);
        
        Campaign pool = [
            SELECT Id, NumberOfContacts, Quality_Score__c
            FROM Campaign WHERE Id = :poolId
        ];
        
            System.debug('DEBUG 42: Pool Retrieved | Id=' + pool.Id + 
        ' | NumberOfContacts=' + pool.NumberOfContacts + 
        ' | Quality_Score__c=' + pool.Quality_Score__c
   		 );
        
        List<AggregateResult> results = [
            SELECT AVG(AI_Match_Score__c) avgScore, AVG(Contact.Years_Experience__c) avgExp
            FROM CampaignMember
            WHERE CampaignId = :poolId AND Status = 'Interested'
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
                WHERE CampaignId = :poolId AND Status = 'Interested'];
        
        // ✅ Query Job Roles
        List<CampaignMember> campaignMembers = [
            SELECT Contact.Job_Role__c 
            FROM CampaignMember 
            WHERE Status = 'Interested' AND CampaignId = :poolId
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
                AND Status = 'Interested'
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
        @AuraEnabled public List<String> skills;
        @AuraEnabled public Decimal experienceYears;
        @AuraEnabled public String location;
        @AuraEnabled public String sentimentTags;
        @AuraEnabled public Boolean isUnlocked;
        @AuraEnabled public DateTime interestDate;
        @AuraEnabled public String jobRole;
        // Full details (only if unlocked)
        @AuraEnabled public String fullName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        
        public CandidateWrapper(CampaignMember member, String tier, Integer index) {
            this.memberId = member.Id;
            this.contactId = member.ContactId;
            this.matchScore = member.AI_Match_Score__c != null ? member.AI_Match_Score__c.intValue() : 0;
            this.sentimentTags = member.Sentiment_Tags__c;
            this.isUnlocked = member.Full_Profile_Unlocked__c;
            this.interestDate = member.Interest_Date__c;
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
            if (this.isUnlocked || tier == 'Professional' || tier == 'Enterprise') {
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
}