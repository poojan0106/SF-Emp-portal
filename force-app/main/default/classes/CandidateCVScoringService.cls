public class CandidateCVScoringService {
    public static void scoreCampaignMembersForContact(Id contactId) {
        if (contactId == null) return;

        Long started = DateTime.now().getTime();
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
        Map<Id, SObject> intents = fetchLatestByContact('Career_Intent__c', contactIds, new List<String>{
            'Id', 'Contact__c', 'Candidate__c', 'Short_Term_Goal__c', 'Medium_Term_Goal__c',
            'Long_Term_Goal__c', 'Aspirational_Goal__c', 'Skills__c', 'Industry_Preferences__c'
        });
        Map<Id, SObject> constraints = fetchLatestByContact('Career_Constraints__c', contactIds, new List<String>{
            'Id', 'Contact__c', 'Preferred_Locations__c', 'Remote_Work_Requirement__c',
            'Min_Salary__c', 'Max_Salary__c', 'Company_Size_Preference__c', 'Culture_Preferences__c'
        });
        ScoringConfig config = loadConfig();
        ensureCampaignMemberStatus(campaignIds, 'CV Review Required');

        List<CampaignMember> updates = new List<CampaignMember>();
        for (CampaignMember member : members) {
            Contact candidate = contacts.get(member.ContactId);
            Campaign campaign = campaigns.get(member.CampaignId);
            if (candidate == null || campaign == null) continue;

            ScoreResult result = calculate(candidate, campaign, member, config, intents.get(candidate.Id), constraints.get(candidate.Id));
            CampaignMember updateMember = new CampaignMember(Id = member.Id);
            putIfFieldExists(updateMember, CampaignMember.SObjectType, 'AI_CV_Score__c', result.score);
            putIfFieldExists(updateMember, CampaignMember.SObjectType, 'AI_CV_Tier__c', result.tier);
            putIfFieldExists(updateMember, CampaignMember.SObjectType, 'AI_CV_Score_Explanation__c', result.explanation);
            putIfFieldExists(updateMember, CampaignMember.SObjectType, 'AI_Protected_Summary__c', buildProtectedSummary(candidate, result));
            putIfFieldExists(updateMember, CampaignMember.SObjectType, 'AI_Protected_Experience__c', buildProtectedExperience(candidate));
            putIfFieldExists(updateMember, CampaignMember.SObjectType, 'AI_Protected_Skills__c', value(candidate, 'R_ATS__Skills__c'));
            if (result.score < config.questionnaireThreshold) {
                updateMember.Status = 'CV Review Required';
            }

            Decimal questionnaire = decimalValue(member, 'Questionnaire_Score__c');
            Decimal combined = calculateCombinedScore(result.score, questionnaire, config);
            putIfFieldExists(updateMember, CampaignMember.SObjectType, 'Combined_Score__c', clamp(combined));
            updates.add(updateMember);
        }

        if (!updates.isEmpty()) {
            try {
                update updates;
                AIAPILogService.logSuccess(
                    'CV Scoring',
                    contactId,
                    null,
                    'CampaignMembers scored: ' + updates.size(),
                    'Success',
                    Integer.valueOf(String.valueOf(DateTime.now().getTime() - started))
                );
            } catch (Exception e) {
                AIAPILogService.logFailure(
                    'CV Scoring',
                    contactId,
                    null,
                    'CampaignMembers scored: ' + updates.size(),
                    e.getMessage(),
                    Integer.valueOf(String.valueOf(DateTime.now().getTime() - started))
                );
                throw e;
            }
        }
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
        addIfFieldExists(fields, CampaignMember.SObjectType, 'AI_CV_Score__c');
        addIfFieldExists(fields, CampaignMember.SObjectType, 'AI_CV_Tier__c');
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

    private static ScoreResult calculate(Contact candidate, Campaign campaign, CampaignMember member, ScoringConfig config, SObject intent, SObject constraints) {
        String candidateSkillText = firstNonBlank(value(candidate, 'R_ATS__Skills__c'), value(intent, 'Skills__c'));
        Decimal skills = scoreSkills(candidateSkillText,
            value(campaign, 'Must_Have_Skills__c'), value(campaign, 'Nice_To_Have_Skills__c'), config);
        Decimal experience = scoreExperience(decimalValue(candidate, 'Years_Experience__c'), value(campaign, 'Job_Seniority__c'), config);
        Decimal location = scoreLocation(candidate, value(campaign, 'Location_Requirement__c'), value(constraints, 'Preferred_Locations__c'), config);
        Decimal salary = scoreSalary(candidate, campaign, constraints, config);
        String goalFit = scoreGoalFit(intent, campaign);

        Decimal total = clamp(skills + experience + location + salary);
        Decimal previousScore = decimalValue(member, 'AI_CV_Score__c');
        String previousTier = value(member, 'AI_CV_Tier__c');
        ScoreResult result = new ScoreResult();
        result.score = total;
        result.tier = total >= config.potentialMatchMin ? 'Potential Match' : total >= config.reviewRequiredMin ? 'Review Required' : 'Poor Match';
        result.explanation =
            'Skills Match: ' + skills + '/' + config.skillsWeightTotal + '\n' +
            'Experience: ' + experience + '/' + config.experienceWeight + '\n' +
            'Location: ' + location + '/' + config.locationWeight + '\n' +
            'Salary Fit: ' + salary + '/' + config.salaryWeight + '\n' +
            'Career Goal Fit: ' + goalFit + '\n' +
            'Strengths/gaps generated from available Campaign and Contact fields.' +
            scoreChangeNote(previousScore, previousTier, result.score, result.tier, config);
        return result;
    }

    private static String scoreChangeNote(Decimal previousScore, String previousTier, Decimal newScore, String newTier, ScoringConfig config) {
        if (previousScore == null && String.isBlank(previousTier)) return '';
        List<String> notes = new List<String>();
        if (previousScore != null && newScore != null) {
            Decimal delta = newScore - previousScore;
            if (delta >= 10) notes.add('now matches stronger by +' + delta.setScale(0) + ' points');
            if (delta <= -10) notes.add('no longer matches as strongly by ' + delta.setScale(0) + ' points');
            if (previousScore < config.questionnaireThreshold && newScore >= config.questionnaireThreshold) notes.add('now meets questionnaire threshold');
            if (previousScore >= config.questionnaireThreshold && newScore < config.questionnaireThreshold) notes.add('no longer meets questionnaire threshold');
        }
        if (String.isNotBlank(previousTier) && String.isNotBlank(newTier) && previousTier != newTier) {
            notes.add('tier changed from ' + previousTier + ' to ' + newTier);
        }
        return notes.isEmpty() ? '' : '\nMatch Change: ' + String.join(notes, '; ') + '.';
    }

    private static Decimal scoreSkills(String candidateSkillsText, String mustText, String niceText, ScoringConfig config) {
        List<String> candidateSkills = parseSkills(candidateSkillsText);
        List<String> must = parseSkills(mustText);
        List<String> nice = parseSkills(niceText);
        if (candidateSkills.isEmpty() || (must.isEmpty() && nice.isEmpty())) return 0;

        Decimal score = 0;
        if (!must.isEmpty()) score += config.skillsWeight * matchRatio(candidateSkills, must);
        if (!nice.isEmpty()) score += config.skillsNiceToHaveWeight * matchRatio(candidateSkills, nice);
        return clampPart(score, config.skillsWeightTotal);
    }

    private static Decimal scoreExperience(Decimal years, String seniority, ScoringConfig config) {
        if (years == null || String.isBlank(seniority)) return 0;
        String level = String.isBlank(seniority) ? '' : seniority.toLowerCase();
        Decimal target = 2;
        if (level.contains('mid')) target = 3;
        if (level.contains('senior')) target = 5;
        if (level.contains('lead') || level.contains('executive')) target = 8;
        Decimal ratio = years / target;
        return clampPart(config.experienceWeight * (ratio > 1 ? 1 : ratio), config.experienceWeight);
    }

    private static Decimal scoreLocation(Contact candidate, String jobLocation, String preferredLocations, ScoringConfig config) {
        if (String.isBlank(jobLocation)) return 0;
        String haystack = (String.valueOf(candidate.MailingCity) + ' ' +
            String.valueOf(candidate.MailingState) + ' ' + String.valueOf(candidate.MailingCountry) + ' ' +
            String.valueOf(preferredLocations)).toLowerCase();
        if (String.isBlank(haystack.replace('null', '').trim())) return 0;
        for (String token : jobLocation.toLowerCase().split('[,;\\s]+')) {
            if (String.isNotBlank(token) && haystack.contains(token)) return config.locationWeight;
        }
        return 0;
    }

    private static Decimal scoreSalary(Contact candidate, Campaign campaign, SObject constraints, ScoringConfig config) {
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
        if (candidateMin == null) candidateMin = decimalValue(constraints, 'Min_Salary__c');
        if (candidateMax == null) candidateMax = decimalValue(constraints, 'Max_Salary__c');
        Decimal jobMin = decimalValue(campaign, 'R_ATS__Minimum_Salary__c');
        Decimal jobMax = decimalValue(campaign, 'R_ATS__Maximum_Salary__c');
        if (candidateMin == null && candidateMax == null) return 0;
        if (jobMin == null && jobMax == null) return 0;

        Decimal low = candidateMin == null ? candidateMax : candidateMin;
        Decimal high = candidateMax == null ? candidateMin : candidateMax;
        Decimal jobLow = jobMin == null ? jobMax : jobMin;
        Decimal jobHigh = jobMax == null ? jobMin : jobMax;
        Boolean overlaps = low <= jobHigh && high >= jobLow;
        return overlaps ? config.salaryWeight : 0;
    }

    private static String scoreGoalFit(SObject intent, Campaign campaign) {
        if (intent == null || campaign == null) return 'No saved career goal context';
        String goals = (
            String.valueOf(value(intent, 'Short_Term_Goal__c')) + ' ' +
            String.valueOf(value(intent, 'Medium_Term_Goal__c')) + ' ' +
            String.valueOf(value(intent, 'Long_Term_Goal__c')) + ' ' +
            String.valueOf(value(intent, 'Aspirational_Goal__c')) + ' ' +
            String.valueOf(value(intent, 'Industry_Preferences__c'))
        ).toLowerCase();
        String campaignText = (
            String.valueOf(campaign.Name) + ' ' +
            String.valueOf(value(campaign, 'Must_Have_Skills__c')) + ' ' +
            String.valueOf(value(campaign, 'Nice_To_Have_Skills__c'))
        ).toLowerCase();
        Integer matches = 0;
        for (String token : campaignText.split('[,;\\s]+')) {
            if (String.isNotBlank(token) && token.length() > 3 && goals.contains(token)) matches++;
        }
        return matches > 0 ? 'Aligned with saved Blakeney goals' : 'No direct goal alignment detected';
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

    private static Decimal calculateCombinedScore(Decimal cvScore, Decimal questionnaireScore, ScoringConfig config) {
        if (questionnaireScore == null) return cvScore;
        Decimal cvWeight = config.cvScoreWeight == null ? 0 : config.cvScoreWeight;
        Decimal questionnaireWeight = config.questionnaireScoreWeight == null ? 0 : config.questionnaireScoreWeight;
        Decimal totalWeight = cvWeight + questionnaireWeight;
        if (totalWeight <= 0) return cvScore;
        return ((cvScore * cvWeight) + (questionnaireScore * questionnaireWeight)) / totalWeight;
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

    private static String firstNonBlank(String first, String second) {
        return String.isNotBlank(first) ? first : second;
    }

    private static Map<Id, SObject> fetchLatestByContact(String objectName, Set<Id> contactIds, List<String> requestedFields) {
        Map<Id, SObject> result = new Map<Id, SObject>();
        if (contactIds == null || contactIds.isEmpty() || !Schema.getGlobalDescribe().containsKey(objectName)) return result;
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap();
        if (!fieldMap.containsKey('Contact__c')) return result;
        List<String> fields = new List<String>();
        for (String fieldName : requestedFields) {
            if (fieldMap.containsKey(fieldName)) fields.add(fieldName);
        }
        if (!fields.contains('Id')) fields.add('Id');
        if (!fields.contains('Contact__c')) fields.add('Contact__c');

        try {
            List<SObject> rows = Database.query(
                'SELECT ' + String.join(fields, ',') + ' FROM ' + objectName +
                ' WHERE Contact__c IN :contactIds ORDER BY LastModifiedDate DESC'
            );
            for (SObject row : rows) {
                Id contactId = (Id) row.get('Contact__c');
                if (contactId != null && !result.containsKey(contactId)) result.put(contactId, row);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, objectName + ' scoring context skipped: ' + e.getMessage());
        }
        return result;
    }

    private static ScoringConfig loadConfig() {
        ScoringConfig config = new ScoringConfig();
        if (!Schema.getGlobalDescribe().containsKey('Scoring_Configuration__mdt')) return config;

        try {
            List<SObject> rows = Database.query(
                'SELECT Skills_Weight_Total__c, Skills_Weight__c, Skills_Weight_Nice_To_Have__c, ' +
                'Experience_Weight__c, Location_Weight__c, Salary_Weight__c, CV_Score_Weight__c, ' +
                'Questionnaire_Score_Weight__c, Questionnaire_Threshold__c, ' +
                'Potential_Match_Min__c, Review_Required_Min__c, Poor_Match_Max__c ' +
                'FROM Scoring_Configuration__mdt WHERE DeveloperName = \'Default\' LIMIT 1'
            );
            if (rows.isEmpty()) return config;
            SObject row = rows[0];
            config.skillsWeightTotal = fallback(decimalValue(row, 'Skills_Weight_Total__c'), config.skillsWeightTotal);
            config.skillsWeight = fallback(decimalValue(row, 'Skills_Weight__c'), config.skillsWeight);
            config.skillsNiceToHaveWeight = fallback(decimalValue(row, 'Skills_Weight_Nice_To_Have__c'), config.skillsNiceToHaveWeight);
            config.experienceWeight = fallback(decimalValue(row, 'Experience_Weight__c'), config.experienceWeight);
            config.locationWeight = fallback(decimalValue(row, 'Location_Weight__c'), config.locationWeight);
            config.salaryWeight = fallback(decimalValue(row, 'Salary_Weight__c'), config.salaryWeight);
            config.cvScoreWeight = fallback(decimalValue(row, 'CV_Score_Weight__c'), config.cvScoreWeight);
            config.questionnaireScoreWeight = fallback(decimalValue(row, 'Questionnaire_Score_Weight__c'), config.questionnaireScoreWeight);
            config.questionnaireThreshold = fallback(decimalValue(row, 'Questionnaire_Threshold__c'), config.questionnaireThreshold);
            config.potentialMatchMin = fallback(decimalValue(row, 'Potential_Match_Min__c'), config.potentialMatchMin);
            config.reviewRequiredMin = fallback(decimalValue(row, 'Review_Required_Min__c'), config.reviewRequiredMin);
            config.poorMatchMax = fallback(decimalValue(row, 'Poor_Match_Max__c'), config.poorMatchMax);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Scoring config fallback used: ' + e.getMessage());
        }
        return config;
    }

    private static Decimal fallback(Decimal value, Decimal fallbackValue) {
        return value == null ? fallbackValue : value;
    }

    private static void ensureCampaignMemberStatus(Set<Id> campaignIds, String statusLabel) {
        if (campaignIds == null || campaignIds.isEmpty() || String.isBlank(statusLabel)) return;
        Set<Id> missing = new Set<Id>(campaignIds);
        for (CampaignMemberStatus existing : [
            SELECT CampaignId
            FROM CampaignMemberStatus
            WHERE CampaignId IN :campaignIds AND Label = :statusLabel
        ]) {
            missing.remove(existing.CampaignId);
        }
        List<CampaignMemberStatus> inserts = new List<CampaignMemberStatus>();
        for (Id campaignId : missing) {
            inserts.add(new CampaignMemberStatus(
                CampaignId = campaignId,
                Label = statusLabel,
                SortOrder = 10,
                HasResponded = true,
                IsDefault = false
            ));
        }
        if (!inserts.isEmpty()) insert inserts;
    }

    private class ScoreResult {
        Decimal score;
        String tier;
        String explanation;
    }

    private class ScoringConfig {
        Decimal skillsWeightTotal = 40;
        Decimal skillsWeight = 30;
        Decimal skillsNiceToHaveWeight = 10;
        Decimal experienceWeight = 30;
        Decimal locationWeight = 15;
        Decimal salaryWeight = 15;
        Decimal cvScoreWeight = 40;
        Decimal questionnaireScoreWeight = 60;
        Decimal questionnaireThreshold = 70;
        Decimal potentialMatchMin = 70;
        Decimal reviewRequiredMin = 40;
        Decimal poorMatchMax = 39;
    }
}