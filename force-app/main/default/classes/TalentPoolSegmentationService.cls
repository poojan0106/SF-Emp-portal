/**
 * ═══════════════════════════════════════════════════════════════════════════
 * TalentPoolSegmentationService.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Service class for managing talent pool segmentation
 * 
 * TASKS COVERED:
 *   - US-045-BE-026: Create sub-pool Campaign hierarchy (Parent → Child)
 *   - US-045-BE-027: Define segmentation categories
 *   - US-045-BE-029: Build skill-to-segment mapping
 *   - US-045-BE-030: Implement dual membership (main pool + sub-pool)
 * 
 * SEGMENTATION CATEGORIES:
 *   - Developers (Engineering, IT, Software)
 *   - Sales (Sales, Business Development)
 *   - Marketing (Marketing, Communications, PR)
 *   - Finance (Finance, Accounting, Banking)
 *   - Operations (Operations, Supply Chain, Logistics)
 *   - Other (Unclassified)
 * 
 * HIERARCHY:
 *   Parent Campaign: "{Employer} - Talent Pool"
 *     └─ Child Campaign: "{Employer} - Developers Pool"
 *     └─ Child Campaign: "{Employer} - Sales Pool"
 *     └─ Child Campaign: "{Employer} - Marketing Pool"
 *     └─ Child Campaign: "{Employer} - Finance Pool"
 *     └─ Child Campaign: "{Employer} - Operations Pool"
 *     └─ Child Campaign: "{Employer} - Other Pool"
 * 
 * AUTHOR: [Your Name]
 * DATE: January 2025
 * ═══════════════════════════════════════════════════════════════════════════
 */
public with sharing class TalentPoolSegmentationService {
    
    // ═══════════════════════════════════════════════════════════════════════
    // TASK US-045-BE-027: SEGMENTATION CATEGORIES
    // ═══════════════════════════════════════════════════════════════════════
    
    /** Enum-like constants for segment categories */
    public static final String SEGMENT_DEVELOPERS = 'Developers';
    public static final String SEGMENT_SALES = 'Sales';
    public static final String SEGMENT_MARKETING = 'Marketing';
    public static final String SEGMENT_FINANCE = 'Finance';
    public static final String SEGMENT_OPERATIONS = 'Operations';
    public static final String SEGMENT_OTHER = 'Other';
    
    /** All available segments in order */
    public static final List<String> ALL_SEGMENTS = new List<String>{
        SEGMENT_DEVELOPERS,
        SEGMENT_SALES,
        SEGMENT_MARKETING,
        SEGMENT_FINANCE,
        SEGMENT_OPERATIONS,
        SEGMENT_OTHER
    };
    
    // ═══════════════════════════════════════════════════════════════════════
    // TASK US-045-BE-029: SKILL-TO-SEGMENT MAPPING
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Maps skills/keywords to segment categories.
     * Case-insensitive matching is performed.
     */
    private static final Map<String, Set<String>> SEGMENT_KEYWORDS = new Map<String, Set<String>>{
        SEGMENT_DEVELOPERS => new Set<String>{
            // Job Titles
            'developer', 'engineer', 'programmer', 'architect', 'devops',
            'software', 'frontend', 'backend', 'fullstack', 'full-stack',
            'mobile', 'ios', 'android', 'web developer', 'sre', 'qa', 'tester',
            'data engineer', 'ml engineer', 'ai engineer', 'platform engineer',
            // Skills
            'java', 'python', 'javascript', 'typescript', 'c++', 'c#', 'ruby',
            'golang', 'rust', 'swift', 'kotlin', 'react', 'angular', 'vue',
            'node.js', 'nodejs', '.net', 'aws', 'azure', 'gcp', 'docker',
            'kubernetes', 'terraform', 'jenkins', 'git', 'sql', 'nosql',
            'mongodb', 'postgresql', 'mysql', 'redis', 'elasticsearch',
            'machine learning', 'deep learning', 'artificial intelligence',
            'api', 'microservices', 'cloud', 'agile', 'scrum',
            // Departments
            'engineering', 'it', 'information technology', 'tech', 'r&d'
        },
        SEGMENT_SALES => new Set<String>{
            // Job Titles
            'sales', 'account executive', 'account manager', 'sdr', 'bdr',
            'sales representative', 'sales manager', 'sales director',
            'business development', 'bd manager', 'partnership', 'channel',
            'enterprise sales', 'inside sales', 'outside sales', 'field sales',
            'sales engineer', 'pre-sales', 'solution consultant',
            'customer success', 'csm', 'relationship manager',
            // Skills
            'salesforce', 'hubspot', 'crm', 'negotiation', 'prospecting',
            'cold calling', 'lead generation', 'pipeline', 'quota',
            'b2b sales', 'b2c sales', 'saas sales', 'enterprise',
            // Departments
            'sales department', 'revenue', 'commercial'
        },
        SEGMENT_MARKETING => new Set<String>{
            // Job Titles
            'marketing', 'marketer', 'brand manager', 'product marketing',
            'content', 'copywriter', 'seo', 'sem', 'ppc', 'social media',
            'digital marketing', 'growth', 'demand generation', 'campaigns',
            'communications', 'pr', 'public relations', 'media relations',
            'creative director', 'art director', 'graphic designer',
            'video producer', 'content creator', 'influencer',
            // Skills
            'google analytics', 'adobe', 'photoshop', 'illustrator',
            'mailchimp', 'marketo', 'pardot', 'hootsuite', 'sprout',
            'facebook ads', 'google ads', 'linkedin ads', 'tiktok',
            'email marketing', 'automation', 'branding', 'storytelling',
            // Departments
            'marketing department', 'creative', 'brand'
        },
        SEGMENT_FINANCE => new Set<String>{
            // Job Titles
            'finance', 'financial', 'accountant', 'accounting', 'cpa',
            'controller', 'cfo', 'treasurer', 'auditor', 'bookkeeper',
            'financial analyst', 'fp&a', 'investment', 'banker', 'banking',
            'tax', 'payroll', 'billing', 'collections', 'credit',
            'risk analyst', 'compliance', 'actuary', 'underwriter',
            // Skills
            'excel', 'quickbooks', 'sap', 'oracle financials', 'netsuite',
            'gaap', 'ifrs', 'budgeting', 'forecasting', 'modeling',
            'financial reporting', 'audit', 'tax preparation', 'valuation',
            // Departments
            'finance department', 'accounting department', 'treasury'
        },
        SEGMENT_OPERATIONS => new Set<String>{
            // Job Titles
            'operations', 'ops', 'supply chain', 'logistics', 'procurement',
            'warehouse', 'inventory', 'fulfillment', 'distribution',
            'project manager', 'program manager', 'pmo', 'scrum master',
            'business analyst', 'process', 'quality', 'lean', 'six sigma',
            'facilities', 'office manager', 'admin', 'executive assistant',
            'hr', 'human resources', 'recruiter', 'talent acquisition',
            'people operations', 'training', 'l&d', 'legal', 'paralegal',
            // Skills
            'project management', 'pmp', 'prince2', 'jira', 'asana',
            'monday', 'trello', 'confluence', 'process improvement',
            'vendor management', 'contract', 'erp', 'sap', 'oracle',
            // Departments
            'operations department', 'supply chain', 'hr department'
        }
    };
    
    // ═══════════════════════════════════════════════════════════════════════
    // MAIN PUBLIC METHODS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * TASK US-045-BE-030: Implements dual membership
     * Adds candidate to both main pool AND matching sub-pool(s).
     * 
     * Called from TalentPoolService after creating main pool membership.
     * 
     * @param candidateId Contact ID of the candidate
     * @param parentCampaignId Main talent pool Campaign ID
     * @param swipeEventId Swipe_Event__c ID for linking
     */
    public static void addToSegmentedPools(
        Id candidateId, 
        Id parentCampaignId,
        Id swipeEventId
    ) {
        // Get candidate's skills and profile for segmentation
        Contact candidate = getCandidateProfile(candidateId);
        
        // Determine which segment(s) the candidate belongs to
        Set<String> matchingSegments = determineSegments(candidate);
        
        // If no matches, default to "Other"
        if (matchingSegments.isEmpty()) {
            matchingSegments.add(SEGMENT_OTHER);
        }
        
        // Get or create sub-pool campaigns
        Map<String, Campaign> subPools = getOrCreateSubPools(parentCampaignId, matchingSegments);
        
        // Create campaign members for each matching sub-pool
        createSubPoolMemberships(candidateId, subPools.values(), swipeEventId);
    }
    
    /**
     * Bulk version for batch processing.
     * Processes multiple candidates efficiently.
     * 
     * @param membershipData List of MembershipInfo records to process
     */
    public static void addToSegmentedPoolsBulk(List<MembershipInfo> membershipData) {
        if (membershipData == null || membershipData.isEmpty()) return;
        
        // Collect all candidate IDs and parent campaign IDs
        Set<Id> candidateIds = new Set<Id>();
        Set<Id> parentCampaignIds = new Set<Id>();
        
        for (MembershipInfo info : membershipData) {
            candidateIds.add(info.candidateId);
            parentCampaignIds.add(info.parentCampaignId);
        }
        
        // Bulk query candidates
        Map<Id, Contact> candidateMap = new Map<Id, Contact>(getCandidateProfiles(candidateIds));
        
        // Determine segments for each candidate
        Map<Id, Set<String>> candidateSegments = new Map<Id, Set<String>>();
        Set<String> allNeededSegments = new Set<String>();
        
        for (MembershipInfo info : membershipData) {
            Contact candidate = candidateMap.get(info.candidateId);
            Set<String> segments = determineSegments(candidate);
            if (segments.isEmpty()) {
                segments.add(SEGMENT_OTHER);
            }
            candidateSegments.put(info.candidateId, segments);
            allNeededSegments.addAll(segments);
        }
        
        // Get or create all needed sub-pools for all parent campaigns
        Map<String, Campaign> allSubPools = getOrCreateSubPoolsBulk(parentCampaignIds, allNeededSegments);
        
        // Create all campaign memberships
        List<CampaignMember> membersToInsert = new List<CampaignMember>();
        List<CampaignMember> membersToUpdate = new List<CampaignMember>();
        Map<String, CampaignMember> existingMembers = getExistingMembers(parentCampaignIds, candidateIds);
        
        for (MembershipInfo info : membershipData) {
            Set<String> segments = candidateSegments.get(info.candidateId);
            
            for (String segment : segments) {
                String subPoolKey = info.parentCampaignId + '_' + segment;
                Campaign subPool = allSubPools.get(subPoolKey);
                
                if (subPool != null) {
                    // Check for duplicate
                    String memberKey = subPool.Id + '_' + info.candidateId;
                    if (!existingMembers.containsKey(memberKey)) {
                        CampaignMember member = new CampaignMember(
                            CampaignId = subPool.Id,
                            ContactId = info.candidateId,
                            Status = 'Interested',
                            Intent_Added_Date__c = Date.today(),
                            Intent_Source__c = 'Swipe',
                            Swipe_Event__c = info.swipeEventId
                        );
                        membersToInsert.add(member);
                        existingMembers.put(memberKey, member); // Prevent duplicates in same batch
                    } else if (
                        info.swipeEventId != null &&
                        existingMembers.get(memberKey).Id != null &&
                        existingMembers.get(memberKey).Swipe_Event__c != info.swipeEventId
                    ) {
                        membersToUpdate.add(new CampaignMember(
                            Id = existingMembers.get(memberKey).Id,
                            Swipe_Event__c = info.swipeEventId,
                            Intent_Source__c = 'Swipe',
                            Intent_Added_Date__c = Date.today()
                        ));
                    }
                }
            }
        }
        
        // Insert with partial success
        if (!membersToInsert.isEmpty()) {
            Database.insert(membersToInsert, false);
        }
        if (!membersToUpdate.isEmpty()) {
            Database.update(membersToUpdate, false);
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TASK US-045-BE-026: SUB-POOL CAMPAIGN HIERARCHY
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Gets existing sub-pools or creates new ones for the given segments.
     * Uses Campaign.ParentId to establish hierarchy.
     * 
     * @param parentCampaignId The main talent pool Campaign ID
     * @param segments Set of segment names to create/find
     * @return Map of segment name to Campaign record
     */
    public static Map<String, Campaign> getOrCreateSubPools(Id parentCampaignId, Set<String> segments) {
        Map<String, Campaign> subPoolMap = new Map<String, Campaign>();
        
        // Query parent campaign for employer info
        Campaign parentCampaign = [
            SELECT Id, Name, Employer__c, Employer__r.Name, RecordTypeId
            FROM Campaign
            WHERE Id = :parentCampaignId
            LIMIT 1
        ];
        
        String employerName = parentCampaign.Employer__r.Name;
        
        // Query existing sub-pools
        List<Campaign> existingSubPools = [
            SELECT Id, Name, Segment_Category__c
            FROM Campaign
            WHERE ParentId = :parentCampaignId
            AND Segment_Category__c IN :segments
        ];
        
        // Map existing sub-pools
        Set<String> existingSegments = new Set<String>();
        for (Campaign subPool : existingSubPools) {
            subPoolMap.put(subPool.Segment_Category__c, subPool);
            existingSegments.add(subPool.Segment_Category__c);
        }
        
        // Create missing sub-pools
        List<Campaign> newSubPools = new List<Campaign>();
        
        for (String segment : segments) {
            if (!existingSegments.contains(segment)) {
                Campaign subPool = new Campaign(
                    Name = employerName + ' - ' + segment + ' Pool',
                    ParentId = parentCampaignId,  // ← Establishes hierarchy
                    Employer__c = parentCampaign.Employer__c,
                    Segment_Category__c = segment,
                    Type = 'Employer Interest Pool',
                    Pool_Type__c = 'Job_Specific',
                    Status = 'In Progress',
                    IsActive = true
                );
                
                // Copy Record Type from parent if exists
                if (parentCampaign.RecordTypeId != null) {
                    subPool.RecordTypeId = parentCampaign.RecordTypeId;
                }
                
                newSubPools.add(subPool);
            }
        }
        
        if (!newSubPools.isEmpty()) {
            insert newSubPools;
            
            // Add to map
            	List<Id> newSubPoolIds = new List<Id>();
            for (Campaign subPool : newSubPools) {
                subPoolMap.put(subPool.Segment_Category__c, subPool);
                newSubPoolIds.add(subPool.Id);
            }
            
            // Add CampaignMemberStatus values to sub-pools
			    TalentPoolService.createTalentPoolStatuses(newSubPoolIds);
        }
        
        return subPoolMap;
    }
    
    /**
     * Bulk version: Gets/creates sub-pools for multiple parent campaigns.
     * 
     * @param parentCampaignIds Set of parent Campaign IDs
     * @param segments Set of all segment names needed
     * @return Map of "{parentId}_{segment}" to Campaign
     */
    private static Map<String, Campaign> getOrCreateSubPoolsBulk(
        Set<Id> parentCampaignIds, 
        Set<String> segments
    ) {
        Map<String, Campaign> subPoolMap = new Map<String, Campaign>();
        
        // Query parent campaigns
        Map<Id, Campaign> parentMap = new Map<Id, Campaign>([
            SELECT Id, Name, Employer__c, Employer__r.Name, RecordTypeId
            FROM Campaign
            WHERE Id IN :parentCampaignIds
        ]);
        
        // Query all existing sub-pools
        List<Campaign> existingSubPools = [
            SELECT Id, Name, ParentId, Segment_Category__c
            FROM Campaign
            WHERE ParentId IN :parentCampaignIds
            AND Segment_Category__c IN :segments
        ];
        
        // Map existing: key = "{parentId}_{segment}"
        Set<String> existingKeys = new Set<String>();
        for (Campaign subPool : existingSubPools) {
            String key = subPool.ParentId + '_' + subPool.Segment_Category__c;
            subPoolMap.put(key, subPool);
            existingKeys.add(key);
        }
        
        // Create missing sub-pools
        List<Campaign> newSubPools = new List<Campaign>();
        
        for (Id parentId : parentCampaignIds) {
            Campaign parent = parentMap.get(parentId);
            if (parent == null) continue;
            
            String employerName = parent.Employer__r.Name;
            
            for (String segment : segments) {
                String key = parentId + '_' + segment;
                
                if (!existingKeys.contains(key)) {
                    Campaign subPool = new Campaign(
                        Name = employerName + ' - ' + segment + ' Pool',
                        ParentId = parentId,
                        Employer__c = parent.Employer__c,
                        Segment_Category__c = segment,
                        Type = 'Employer Interest Pool',
                        Pool_Type__c = 'Job_Specific',
                        Status = 'In Progress',
                        IsActive = true
                    );
                    
                    if (parent.RecordTypeId != null) {
                        subPool.RecordTypeId = parent.RecordTypeId;
                    }
                    
                    newSubPools.add(subPool);
                    existingKeys.add(key); // Prevent duplicates
                }
            }
        }
        
        if (!newSubPools.isEmpty()) {
            insert newSubPools;
			
			List<Id> newSubPoolIds = new List<Id>();            
            for (Campaign subPool : newSubPools) {
                String key = subPool.ParentId + '_' + subPool.Segment_Category__c;
                subPoolMap.put(key, subPool);
                newSubPoolIds.add(subPool.Id);
            }
            
            // Add CampaignMemberStatus values to sub-pools
			   TalentPoolService.createTalentPoolStatuses(newSubPoolIds);
        }
        
        return subPoolMap;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // SEGMENT DETERMINATION LOGIC
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Determines which segment(s) a candidate belongs to based on:
     * - Current/Target job title
     * - Skills
     * - Industry experience
     * - Department
     * 
     * @param candidate Contact record with profile fields
     * @return Set of matching segment names (can be multiple)
     */
    public static Set<String> determineSegments(Contact candidate) {
        Set<String> matchingSegments = new Set<String>();
        
        if (candidate == null) return matchingSegments;
        
        // Build searchable text from candidate profile
        String searchText = buildSearchText(candidate);
        
        if (String.isBlank(searchText)) return matchingSegments;
        
        // Search for keyword matches in each segment
        for (String segment : SEGMENT_KEYWORDS.keySet()) {
            Set<String> keywords = SEGMENT_KEYWORDS.get(segment);
            
            for (String keyword : keywords) {
                if (searchText.contains(keyword.toLowerCase())) {
                    matchingSegments.add(segment);
                    break; // Found match for this segment, move to next
                }
            }
        }
        
        return matchingSegments;
    }
    
    /**
     * Overloaded method: Determines segments from a CandidateProfile wrapper.
     * Use this when you cannot query Contact with child relationships.
     * 
     * @param profile CandidateProfile wrapper with profile data
     * @return Set of matching segment names
     */
    public static Set<String> determineSegments(CandidateProfile profile) {
        Set<String> matchingSegments = new Set<String>();
        
        if (profile == null) return matchingSegments;
        
        // Build searchable text from profile
        String searchText = buildSearchTextFromProfile(profile);
        
        if (String.isBlank(searchText)) return matchingSegments;
        
        // Search for keyword matches in each segment
        for (String segment : SEGMENT_KEYWORDS.keySet()) {
            Set<String> keywords = SEGMENT_KEYWORDS.get(segment);
            
            for (String keyword : keywords) {
                if (searchText.contains(keyword.toLowerCase())) {
                    matchingSegments.add(segment);
                    break;
                }
            }
        }
        
        return matchingSegments;
    }
    
    /**
     * Builds searchable text from CandidateProfile wrapper.
     */
    private static String buildSearchTextFromProfile(CandidateProfile profile) {
        List<String> textParts = new List<String>();
        
        if (String.isNotBlank(profile.title)) textParts.add(profile.title);
        if (String.isNotBlank(profile.skills)) textParts.add(profile.skills);
        if (String.isNotBlank(profile.department)) textParts.add(profile.department);
        if (String.isNotBlank(profile.industryExperience)) textParts.add(profile.industryExperience);
        if (String.isNotBlank(profile.targetRole)) textParts.add(profile.targetRole);
        if (String.isNotBlank(profile.targetIndustry)) textParts.add(profile.targetIndustry);
        
        return String.join(textParts, ' ').toLowerCase();
    }
    
    /**
     * Wrapper class for candidate profile data.
     * Use when child relationships cannot be queried/assigned.
     */
    public class CandidateProfile {
        public Id contactId;
        public String title;
        public String department;
        public String skills;
        public String industryExperience;
        public String targetRole;
        public String targetIndustry;
        
        public CandidateProfile() {}
        
        public CandidateProfile(Contact c) {
            this.contactId = c.Id;
            this.title = c.Title;
            this.department = c.Department;
            this.skills = c.R_ATS__Skills__c;
            this.industryExperience = c.Industry_Experience__c;
        }
        
        public CandidateProfile withCareerIntent(Career_Intent__c intent) {
            if (intent != null) {
                this.targetRole = intent.Target_Role__c;
                this.targetIndustry = intent.Short_Term_Industry__c;
            }
            return this;
        }
    }
    
    /**
     * Builds a searchable text string from candidate profile fields.
     */
    private static String buildSearchText(Contact candidate) {
        System.debug('buildSearchText START');
        List<String> textParts = new List<String>();
        
        // Job title fields
        if (String.isNotBlank(candidate.Title)) {
            textParts.add(candidate.Title);
            System.debug('Title added=' + candidate.Title);
        }
        
        // Skills field (assuming comma or semicolon separated)
        if (String.isNotBlank(candidate.R_ATS__Skills__c)) {
            textParts.add(candidate.R_ATS__Skills__c);
            System.debug('Skills added=' + candidate.R_ATS__Skills__c);
        }
        
        // Department
        if (String.isNotBlank(candidate.Department)) {
            textParts.add(candidate.Department);
            System.debug('Department added=' + candidate.Department);
        }
        
        // Industry experience
        if (String.isNotBlank(candidate.Industry_Experience__c)) {
            textParts.add(candidate.Industry_Experience__c);
            System.debug('IndustryExperience added=' + candidate.Industry_Experience__c);
        }
        
        // Career Intent target role (from related record)
        if (candidate.Career_Intents__r != null && !candidate.Career_Intents__r.isEmpty()) {
            Career_Intent__c intent = candidate.Career_Intents__r[0];
            System.debug('Career intent found=' + intent.Id);
            if (String.isNotBlank(intent.Target_Role__c)) {
                textParts.add(intent.Target_Role__c);
                System.debug('TargetRole added=' + intent.Target_Role__c);
            }
            if (String.isNotBlank(intent.Short_Term_Industry__c)) {
                textParts.add(intent.Short_Term_Industry__c);
                System.debug('ShortTermIndustry added=' + intent.Short_Term_Industry__c);
            }
        }
        
        // Combine and lowercase for matching
        return String.join(textParts, ' ').toLowerCase();
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // HELPER METHODS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Queries candidate profile with all fields needed for segmentation.
     */
    private static Contact getCandidateProfile(Id candidateId) {
        return [
            SELECT Id, Title, Department, R_ATS__Skills__c, Industry_Experience__c,
                   (SELECT Target_Role__c, Short_Term_Industry__c 
                    FROM Career_Intents__r 
                    ORDER BY CreatedDate DESC 
                    LIMIT 1)
            FROM Contact
            WHERE Id = :candidateId
            LIMIT 1
        ];
    }
    
    /**
     * Bulk query candidate profiles.
     */
    private static List<Contact> getCandidateProfiles(Set<Id> candidateIds) {
        return [
            SELECT Id, Title, Department, R_ATS__Skills__c, Industry_Experience__c,
                   (SELECT Target_Role__c, Short_Term_Industry__c 
                    FROM Career_Intents__r 
                    ORDER BY CreatedDate DESC 
                    LIMIT 1)
            FROM Contact
            WHERE Id IN :candidateIds
        ];
    }
    
    /**
     * Creates campaign memberships for sub-pools.
     */
    private static void createSubPoolMemberships(
        Id candidateId, 
        List<Campaign> subPools,
        Id swipeEventId
    ) {
        // Check for existing memberships to prevent duplicates
        Set<Id> subPoolIds = new Set<Id>();
        for (Campaign c : subPools) {
            subPoolIds.add(c.Id);
        }
        
        Map<Id, CampaignMember> existingByPoolId = new Map<Id, CampaignMember>();
        for (CampaignMember existing : [
            SELECT Id, CampaignId, Swipe_Event__c
            FROM CampaignMember 
            WHERE CampaignId IN :subPoolIds 
            AND ContactId = :candidateId
        ]) {
            existingByPoolId.put(existing.CampaignId, existing);
        }
        
        // Create new memberships
        List<CampaignMember> newMembers = new List<CampaignMember>();
        List<CampaignMember> membersToUpdate = new List<CampaignMember>();
        
        for (Campaign subPool : subPools) {
            if (!existingByPoolId.containsKey(subPool.Id)) {
                CampaignMember member = new CampaignMember(
                    CampaignId = subPool.Id,
                    ContactId = candidateId,
                    Status = 'Interested',
                    Intent_Added_Date__c = Date.today(),
                    Intent_Source__c = 'Swipe',
                    Swipe_Event__c = swipeEventId
                );
                newMembers.add(member);
            } else if (
                swipeEventId != null &&
                existingByPoolId.get(subPool.Id).Swipe_Event__c != swipeEventId
            ) {
                membersToUpdate.add(new CampaignMember(
                    Id = existingByPoolId.get(subPool.Id).Id,
                    Swipe_Event__c = swipeEventId,
                    Intent_Source__c = 'Swipe',
                    Intent_Added_Date__c = Date.today()
                ));
            }
        }
        
        if (!newMembers.isEmpty()) {
            Database.insert(newMembers, false);
        }
        if (!membersToUpdate.isEmpty()) {
            Database.update(membersToUpdate, false);
        }
    }
    
    /**
     * Gets existing campaign members to prevent duplicates and repair swipe links.
     */
    private static Map<String, CampaignMember> getExistingMembers(Set<Id> campaignIds, Set<Id> contactIds) {
        Map<String, CampaignMember> membersByKey = new Map<String, CampaignMember>();
        
        // Get all sub-pool IDs
        Set<Id> allPoolIds = new Set<Id>(campaignIds);
        for (Campaign subPool : [SELECT Id FROM Campaign WHERE ParentId IN :campaignIds]) {
            allPoolIds.add(subPool.Id);
        }
        
        // Query existing members
        for (CampaignMember m : [
            SELECT Id, CampaignId, ContactId, Swipe_Event__c
            FROM CampaignMember 
            WHERE CampaignId IN :allPoolIds 
            AND ContactId IN :contactIds
        ]) {
            membersByKey.put(m.CampaignId + '_' + m.ContactId, m);
        }
        
        return membersByKey;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // DATA STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Data structure for bulk membership operations.
     */
    public class MembershipInfo {
        public Id candidateId;
        public Id parentCampaignId;
        public Id swipeEventId;
        
        public MembershipInfo(Id candidateId, Id parentCampaignId, Id swipeEventId) {
            this.candidateId = candidateId;
            this.parentCampaignId = parentCampaignId;
            this.swipeEventId = swipeEventId;
        }
    }
}