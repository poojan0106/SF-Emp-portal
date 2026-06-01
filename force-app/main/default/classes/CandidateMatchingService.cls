/**
 * CandidateMatchingService
 * AI-powered candidate matching for jobs and talent pools
 */
public class CandidateMatchingService {
    
    public static void matchCandidatesToJob(Id jobId, Id accountId) {
        Campaign job = [
            SELECT Id, Name, Must_Have_Skills__c, Nice_To_Have_Skills__c, 
                   Job_Seniority__c, Location_Requirement__c
            FROM Campaign WHERE Id = :jobId
        ];
        
        // Get talent pool for this employer
        List<Campaign> talentPools = [
            SELECT Id FROM Campaign 
            WHERE Employer__c = :accountId 
            AND RecordType.DeveloperName = 'Talent_Pool'
            AND IsActive = true
        ];
        
        if (talentPools.isEmpty()) return;
        
        // Get candidates from talent pool
        List<CampaignMember> poolMembers = [
            SELECT Id, ContactId, Contact.MailingCity, AI_Match_Score__c
            FROM CampaignMember
            WHERE CampaignId IN :talentPools
            AND Status = 'Interested'
        ];
        
        Set<Id> contactIds = new Set<Id>();
        for (CampaignMember member : poolMembers) {
            contactIds.add(member.ContactId);
        }
        
        // Get candidate skills
        Map<Id, Contact> candidates = new Map<Id, Contact>([
            SELECT Id, R_ATS__Skills__c, Years_Experience__c, MailingCity
            FROM Contact WHERE Id IN :contactIds
        ]);
        
        // Calculate match scores
        List<String> mustHaveSkills = parseSkills(job.Must_Have_Skills__c);
        List<String> niceToHaveSkills = parseSkills(job.Nice_To_Have_Skills__c);
        
        Integer matchingCount = 0;
        for (CampaignMember member : poolMembers) {
            Contact candidate = candidates.get(member.ContactId);
            if (candidate != null) {
                Integer score = calculateMatchScore(candidate, mustHaveSkills, niceToHaveSkills, job);
                member.AI_Match_Score__c = score;
                if (score >= 70) matchingCount++;
            }
        }
        
        update poolMembers;
        
        // Update job matching count
        job.Matching_Candidate_Count__c = matchingCount;
        update job;
    }
    
    public static void calculateMatchScore(Id campaignMemberId) {
        CampaignMember member = [
            SELECT Id, ContactId, CampaignId, Campaign.Employer__c
            FROM CampaignMember WHERE Id = :campaignMemberId
        ];
        
        Contact candidate = [
            SELECT Id, R_ATS__Skills__c, Years_Experience__c, MailingCity
            FROM Contact WHERE Id = :member.ContactId
        ];
        
        // Get employer's typical requirements
        Account employer = [
            SELECT Id, Typical_Departments__c, Industry
            FROM Account WHERE Id = :member.Campaign.Employer__c
        ];
        
        // Simple scoring based on profile completeness and industry match
        Integer score = 50; // Base score
        
        if (String.isNotBlank(candidate.R_ATS__Skills__c)) score += 20;
        if (candidate.Years_Experience__c != null && candidate.Years_Experience__c > 0) score += 15;
        if (String.isNotBlank(candidate.MailingCity)) score += 15;
        
        member.AI_Match_Score__c = Math.min(score, 100);
        update member;
    }
    
    private static List<String> parseSkills(String skillsJson) {
        if (String.isBlank(skillsJson)) return new List<String>();
        
        try {
            Object parsed = JSON.deserializeUntyped(skillsJson);
            if (parsed instanceof List<Object>) {
                List<String> skills = new List<String>();
                for (Object skill : (List<Object>) parsed) {
                    skills.add(String.valueOf(skill).toLowerCase());
                }
                return skills;
            }
        } catch (Exception e) {
            // If not JSON, treat as comma-separated
            return skillsJson.toLowerCase().split(',');
        }
        return new List<String>();
    }
    
    private static Integer calculateMatchScore(Contact candidate, List<String> mustHave, List<String> niceToHave, Campaign job) {
        Integer score = 40; // Base score
        
        List<String> candidateSkills = new List<String>();
        if (String.isNotBlank(candidate.R_ATS__Skills__c)) {
            candidateSkills = candidate.R_ATS__Skills__c.toLowerCase().split('[,;\\s]+');
        }
        
        // Check must-have skills (up to 40 points)
        Integer mustHaveMatches = 0;
        for (String skill : mustHave) {
            for (String candidateSkill : candidateSkills) {
                if (candidateSkill.contains(skill) || skill.contains(candidateSkill)) {
                    mustHaveMatches++;
                    break;
                }
            }
        }
        if (!mustHave.isEmpty()) {
            score += (mustHaveMatches * 40) / mustHave.size();
        }
        
        // Check nice-to-have skills (up to 20 points)
        Integer niceToHaveMatches = 0;
        for (String skill : niceToHave) {
            for (String candidateSkill : candidateSkills) {
                if (candidateSkill.contains(skill) || skill.contains(candidateSkill)) {
                    niceToHaveMatches++;
                    break;
                }
            }
        }
        if (!niceToHave.isEmpty()) {
            score += (niceToHaveMatches * 20) / niceToHave.size();
        }
        
        return Math.min(score, 100);
    }
}