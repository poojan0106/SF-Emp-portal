public class CandidateCVScoringService {
    public static void scoreCampaignMembersForContact(Id contactId) {
        if (contactId == null) return;

        List<CampaignMember> members = fetchMembers(contactId);
        if (members.isEmpty()) return;

        Set<Id> contactIds = new Set<Id>();
        Set<Id> campaignIds = new Set<Id>();
        for (CampaignMember member : members) {
            if (member.ContactId != null) contactIds.add(member.ContactId);
            if (member.CampaignId != null) campaignIds.add(member.CampaignId);
        }

        Map<Id, Contact> contacts = fetchContacts(contactIds);
        Map<Id, Campaign> campaigns = fetchCampaigns(campaignIds);

        List<CampaignMember> updates = new List<CampaignMember>();
        for (CampaignMember member : members) {
            Contact candidate = contacts.get(member.ContactId);
            Campaign campaign = campaigns.get(member.CampaignId);
            if (candidate == null || campaign == null) continue;

            ScoreResult result = calculate(candidate, campaign, member);
            CampaignMember updateMember = new CampaignMember(Id = member.Id);
            putIfFieldExists(updateMember, CampaignMember.SObjectType, 'AI_CV_Score__c', result.score);
            putIfFieldExists(updateMember, CampaignMember.SObjectType, 'AI_CV_Tier__c', result.tier);
            putIfFieldExists(updateMember, CampaignMember.SObjectType, 'AI_CV_Score_Explanation__c', result.explanation);
            putIfFieldExists(updateMember, CampaignMember.SObjectType, 'AI_Protected_Summary__c', buildProtectedSummary(candidate, result));
            putIfFieldExists(updateMember, CampaignMember.SObjectType, 'AI_Protected_Experience__c', buildProtectedExperience(candidate));
            putIfFieldExists(updateMember, CampaignMember.SObjectType, 'AI_Protected_Skills__c', value(candidate, 'R_ATS__Skills__c'));

            Decimal questionnaire = decimalValue(member, 'Questionnaire_Score__c');
            Decimal combined = questionnaire == null ? result.score : ((result.score * 0.4) + (questionnaire * 0.6));
            putIfFieldExists(updateMember, CampaignMember.SObjectType, 'Combined_Score__c', clamp(combined));
            updates.add(updateMember);
        }

        if (!updates.isEmpty()) update updates;
    }

    public static void scoreCampaignMember(Id campaignMemberId) {
        if (campaignMemberId == null) return;
        List<CampaignMember> rows = [
            SELECT Id, ContactId
            FROM CampaignMember
            WHERE Id = :campaignMemberId
            LIMIT 1
        ];
        if (!rows.isEmpty()) scoreCampaignMembersForContact(rows[0].ContactId);
    }

    private static List<CampaignMember> fetchMembers(Id contactId) {
        Set<String> fields = new Set<String>{ 'Id', 'ContactId', 'CampaignId', 'Status' };
        addIfFieldExists(fields, CampaignMember.SObjectType, 'Questionnaire_Score__c');
        String soql = 'SELECT ' + String.join(new List<String>(fields), ',') +
            ' FROM CampaignMember WHERE ContactId = :contactId';
        return Database.query(soql);
    }

    private static Map<Id, Contact> fetchContacts(Set<Id> contactIds) {
        if (contactIds.isEmpty()) return new Map<Id, Contact>();
        Set<String> fields = new Set<String>{ 'Id', 'MailingCity', 'MailingState', 'MailingCountry', 'Title' };
        addIfFieldExists(fields, Contact.SObjectType, 'R_ATS__Skills__c');
        addIfFieldExists(fields, Contact.SObjectType, 'R_ATS__Candidate_Summary__c');
        addIfFieldExists(fields, Contact.SObjectType, 'Candidate_Summary__c');
        addIfFieldExists(fields, Contact.SObjectType, 'Years_Experience__c');
        addIfFieldExists(fields, Contact.SObjectType, 'R_ATS__Minimum_Salary__c');
        addIfFieldExists(fields, Contact.SObjectType, 'R_ATS__Maximum_Salary__c');
        addIfFieldExists(fields, Contact.SObjectType, 'Min_Salary_Expectation__c');
        addIfFieldExists(fields, Contact.SObjectType, 'Max_Salary_Expectation__c');

        String soql = 'SELECT ' + String.join(new List<String>(fields), ',') +
            ' FROM Contact WHERE Id IN :contactIds';
        return new Map<Id, Contact>((List<Contact>) Database.query(soql));
    }

    private static Map<Id, Campaign> fetchCampaigns(Set<Id> campaignIds) {
        if (campaignIds.isEmpty()) return new Map<Id, Campaign>();
        Set<String> fields = new Set<String>{ 'Id', 'Name' };
        addIfFieldExists(fields, Campaign.SObjectType, 'Must_Have_Skills__c');
        addIfFieldExists(fields, Campaign.SObjectType, 'Nice_To_Have_Skills__c');
        addIfFieldExists(fields, Campaign.SObjectType, 'Location_Requirement__c');
        addIfFieldExists(fields, Campaign.SObjectType, 'Job_Seniority__c');
        addIfFieldExists(fields, Campaign.SObjectType, 'R_ATS__Minimum_Salary__c');
        addIfFieldExists(fields, Campaign.SObjectType, 'R_ATS__Maximum_Salary__c');

        String soql = 'SELECT ' + String.join(new List<String>(fields), ',') +
            ' FROM Campaign WHERE Id IN :campaignIds';
        return new Map<Id, Campaign>((List<Campaign>) Database.query(soql));
    }

    private static ScoreResult calculate(Contact candidate, Campaign campaign, CampaignMember member) {
        Decimal skills = scoreSkills(value(candidate, 'R_ATS__Skills__c'),
            value(campaign, 'Must_Have_Skills__c'), value(campaign, 'Nice_To_Have_Skills__c'));
        Decimal experience = scoreExperience(decimalValue(candidate, 'Years_Experience__c'), value(campaign, 'Job_Seniority__c'));
        Decimal location = scoreLocation(candidate, value(campaign, 'Location_Requirement__c'));
        Decimal salary = scoreSalary(candidate, campaign);

        Decimal total = clamp(skills + experience + location + salary);
        ScoreResult result = new ScoreResult();
        result.score = total;
        result.tier = total >= 70 ? 'Potential Match' : total >= 40 ? 'Review Required' : 'Poor Match';
        result.explanation =
            'Skills Match: ' + skills + '/40\n' +
            'Experience: ' + experience + '/30\n' +
            'Location: ' + location + '/15\n' +
            'Salary Fit: ' + salary + '/15\n' +
            'Strengths/gaps generated from available Campaign and Contact fields.';
        return result;
    }

    private static Decimal scoreSkills(String candidateSkillsText, String mustText, String niceText) {
        List<String> candidateSkills = parseSkills(candidateSkillsText);
        List<String> must = parseSkills(mustText);
        List<String> nice = parseSkills(niceText);
        if (candidateSkills.isEmpty() || (must.isEmpty() && nice.isEmpty())) return 0;

        Decimal score = 0;
        if (!must.isEmpty()) score += 30 * matchRatio(candidateSkills, must);
        if (!nice.isEmpty()) score += 10 * matchRatio(candidateSkills, nice);
        return clampPart(score, 40);
    }

    private static Decimal scoreExperience(Decimal years, String seniority) {
        if (years == null || String.isBlank(seniority)) return 0;
        String level = String.isBlank(seniority) ? '' : seniority.toLowerCase();
        Decimal target = 2;
        if (level.contains('mid')) target = 3;
        if (level.contains('senior')) target = 5;
        if (level.contains('lead') || level.contains('executive')) target = 8;
        Decimal ratio = years / target;
        return clampPart(30 * (ratio > 1 ? 1 : ratio), 30);
    }

    private static Decimal scoreLocation(Contact candidate, String jobLocation) {
        if (String.isBlank(jobLocation)) return 0;
        String haystack = (String.valueOf(candidate.MailingCity) + ' ' +
            String.valueOf(candidate.MailingState) + ' ' + String.valueOf(candidate.MailingCountry)).toLowerCase();
        if (String.isBlank(haystack.replace('null', '').trim())) return 0;
        for (String token : jobLocation.toLowerCase().split('[,;\\s]+')) {
            if (String.isNotBlank(token) && haystack.contains(token)) return 15;
        }
        return 0;
    }

    private static Decimal scoreSalary(Contact candidate, Campaign campaign) {
        Decimal candidateMin = firstDecimalValue(candidate, new List<String>{
            'R_ATS__Minimum_Salary__c',
            'Min_Salary_Expectation__c',
            'Minimum_Salary__c'
        });
        Decimal candidateMax = firstDecimalValue(candidate, new List<String>{
            'R_ATS__Maximum_Salary__c',
            'Max_Salary_Expectation__c',
            'Maximum_Salary__c'
        });
        Decimal jobMin = decimalValue(campaign, 'R_ATS__Minimum_Salary__c');
        Decimal jobMax = decimalValue(campaign, 'R_ATS__Maximum_Salary__c');
        if (candidateMin == null && candidateMax == null) return 0;
        if (jobMin == null && jobMax == null) return 0;

        Decimal low = candidateMin == null ? candidateMax : candidateMin;
        Decimal high = candidateMax == null ? candidateMin : candidateMax;
        Decimal jobLow = jobMin == null ? jobMax : jobMin;
        Decimal jobHigh = jobMax == null ? jobMin : jobMax;
        Boolean overlaps = low <= jobHigh && high >= jobLow;
        return overlaps ? 15 : 0;
    }

    private static String buildProtectedSummary(Contact candidate, ScoreResult result) {
        String summary = value(candidate, 'R_ATS__Candidate_Summary__c');
        if (String.isBlank(summary)) summary = value(candidate, 'Candidate_Summary__c');
        if (String.isBlank(summary)) summary = 'Protected candidate summary generated from parsed CV data.';
        return summary + '\n\nAI CV Score: ' + result.score + ' (' + result.tier + ')';
    }

    private static String buildProtectedExperience(Contact candidate) {
        Decimal years = decimalValue(candidate, 'Years_Experience__c');
        String title = String.isBlank(candidate.Title) ? 'Role experience available from parsed CV.' : candidate.Title;
        return title + (years == null ? '' : '\nYears experience: ' + years);
    }

    private static Decimal matchRatio(List<String> candidateSkills, List<String> requiredSkills) {
        if (candidateSkills.isEmpty() || requiredSkills.isEmpty()) return 0;
        Integer matches = 0;
        for (String requiredSkill : requiredSkills) {
            for (String candidateSkill : candidateSkills) {
                if (candidateSkill.contains(requiredSkill) || requiredSkill.contains(candidateSkill)) {
                    matches++;
                    break;
                }
            }
        }
        return Decimal.valueOf(matches) / Decimal.valueOf(requiredSkills.size());
    }

    private static List<String> parseSkills(String text) {
        List<String> skills = new List<String>();
        if (String.isBlank(text)) return skills;
        String cleaned = text.replace('[', '').replace(']', '').replace('"', '');
        for (String part : cleaned.split('[,;\\n]+')) {
            String skill = part.trim().toLowerCase();
            if (String.isNotBlank(skill)) skills.add(skill);
        }
        return skills;
    }

    private static Decimal clamp(Decimal score) {
        if (score == null) return null;
        if (score < 0) score = 0;
        if (score > 100) score = 100;
        return score.setScale(0);
    }

    private static Decimal clampPart(Decimal score, Decimal max) {
        if (score == null || score < 0) return 0;
        if (score > max) return max;
        return score.setScale(0);
    }

    private static void addIfFieldExists(Set<String> fields, Schema.SObjectType typeRef, String fieldName) {
        if (typeRef.getDescribe().fields.getMap().containsKey(fieldName)) fields.add(fieldName);
    }

    private static void putIfFieldExists(SObject row, Schema.SObjectType typeRef, String fieldName, Object value) {
        if (typeRef.getDescribe().fields.getMap().containsKey(fieldName)) row.put(fieldName, value);
    }

    private static String value(SObject row, String fieldName) {
        try {
            Object val = row.get(fieldName);
            return val == null ? null : String.valueOf(val);
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal decimalValue(SObject row, String fieldName) {
        try {
            Object val = row.get(fieldName);
            if (val == null) return null;
            if (val instanceof Decimal) return (Decimal) val;
            if (val instanceof Integer) return Decimal.valueOf((Integer) val);
            return Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal firstDecimalValue(SObject row, List<String> fieldNames) {
        for (String fieldName : fieldNames) {
            Decimal value = decimalValue(row, fieldName);
            if (value != null) return value;
        }
        return null;
    }

    private class ScoreResult {
        Decimal score;
        String tier;
        String explanation;
    }
}
