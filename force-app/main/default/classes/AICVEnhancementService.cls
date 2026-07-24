public class AICVEnhancementService {
    private static final String ONBOARDING_TEMPLATE = 'Blakeney_Onboarding_Invitation_Static';

    public static void enhanceContact(Id contactId) {
        if (contactId == null) return;

        Contact con = fetchContact(contactId);
        if (con == null) return;

        String originalSkills = value(con, 'R_ATS__Skills__c');
        String cvText = value(con, 'R_ATS__Text_CV__c');
        Map<String, Object> aiData = enhanceWithClaude(con, originalSkills, cvText);
        String aiSkills = stringValue(aiData.get('skills'));
        String normalizedSkills = normalizeSkills(String.isNotBlank(aiSkills) ? aiSkills : originalSkills);
        String summary = stringValue(aiData.get('summary'));
        if (String.isBlank(summary)) summary = buildSummary(con, normalizedSkills, cvText);
        String flags = stringValue(aiData.get('flags'));
        if (String.isBlank(flags)) flags = buildFlags(cvText);
        Decimal marketabilityScore = decimalFromObject(aiData.get('marketabilityScore'));
        if (marketabilityScore == null) {
            marketabilityScore = calculateMarketabilityScore(con, normalizedSkills, summary, flags);
        }

        Contact updateContact = new Contact(Id = con.Id);
        putFirstExisting(updateContact, Contact.SObjectType, new List<String>{ 'R_ATS__Skills_Original__c', 'Skills_Original__c' }, originalSkills);
        putIfFieldExists(updateContact, Contact.SObjectType, 'R_ATS__Skills__c', normalizedSkills);
        putFirstExisting(updateContact, Contact.SObjectType, new List<String>{ 'R_ATS__Candidate_Summary__c', 'Candidate_Summary__c' }, summary);
        putFirstExisting(updateContact, Contact.SObjectType, new List<String>{ 'R_ATS__Candidate_Flags__c', 'Candidate_Flags__c' }, flags);
        putIfFieldExists(updateContact, Contact.SObjectType, 'Marketability_Score__c', marketabilityScore);
        update updateContact;

        try {
            CandidateCVScoringService.scoreCampaignMembersForContact(con.Id);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'CampaignMember scoring failed after enhancement; Contact enhancement kept: ' + e.getMessage());
        }
        sendOnboardingInvitation(con.Id, con.Email, summary, normalizedSkills);
        publishEnhancementEvent(con.Id, String.isNotBlank(summary), String.isNotBlank(normalizedSkills));
    }

    public static String normalizeSkills(String skillsText) {
        if (String.isBlank(skillsText)) return null;

        Map<String, String> mapping = loadSkillMapping();
        Set<String> seen = new Set<String>();
        List<String> normalized = new List<String>();

        for (String rawSkill : skillsText.split('[,;\\n]+')) {
            String cleaned = rawSkill == null ? '' : rawSkill.trim();
            if (String.isBlank(cleaned)) continue;

            String key = cleaned.toLowerCase();
            String canonical = mapping.containsKey(key) ? mapping.get(key) : cleaned;
            String dedupeKey = canonical.toLowerCase();
            if (!seen.contains(dedupeKey)) {
                seen.add(dedupeKey);
                normalized.add(canonical);
            }
        }

        return normalized.isEmpty() ? null : String.join(normalized, ', ');
    }

    private static Map<String, Object> enhanceWithClaude(Contact con, String skills, String cvText) {
        if (String.isBlank(cvText) && String.isBlank(skills)) return new Map<String, Object>();
        if (Test.isRunningTest()) return new Map<String, Object>();
        String prompt =
            'Analyze this candidate CV/profile. Return ONLY valid JSON with keys: ' +
            'skills (comma-separated canonical skills), summary (3-4 professional paragraphs), ' +
            'flags (newline-separated risks: employment gaps over 6 months, frequent job changes, qualification mismatches, or \"No major risk flags detected\"), ' +
            'marketabilityScore (0-100). Use Australian recruitment terminology. No markdown.';
        try {
            return ClaudeAPIService.extractStructuredData(
                'Name: ' + con.FirstName + ' ' + con.LastName +
                '\nTitle: ' + con.Title +
                '\nParsed skills: ' + skills +
                '\nCV Text:\n' + cvText,
                prompt
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Claude enhancement failed; static fallback used: ' + e.getMessage());
            return new Map<String, Object>();
        }
    }

    private static Contact fetchContact(Id contactId) {
        Set<String> fields = new Set<String>{
            'Id', 'FirstName', 'LastName', 'Email', 'Title', 'Description', 'MailingCity',
            'MailingState', 'MailingCountry'
        };
        addIfFieldExists(fields, Contact.SObjectType, 'R_ATS__Skills__c');
        addIfFieldExists(fields, Contact.SObjectType, 'R_ATS__Text_CV__c');
        addIfFieldExists(fields, Contact.SObjectType, 'Years_Experience__c');
        addIfFieldExists(fields, Contact.SObjectType, 'R_ATS__Minimum_Salary__c');
        addIfFieldExists(fields, Contact.SObjectType, 'R_ATS__Maximum_Salary__c');

        String soql = 'SELECT ' + String.join(new List<String>(fields), ',') +
            ' FROM Contact WHERE Id = :contactId LIMIT 1';
        List<Contact> rows = Database.query(soql);
        return rows.isEmpty() ? null : rows[0];
    }

    private static Map<String, String> loadSkillMapping() {
        Map<String, String> mapping = new Map<String, String>();
        if (!Schema.getGlobalDescribe().containsKey('Skill_Mapping__mdt')) return mapping;

        for (SObject row : Database.query(
            'SELECT Original_Term__c, Canonical_Term__c FROM Skill_Mapping__mdt'
        )) {
            String original = String.valueOf(row.get('Original_Term__c'));
            String canonical = String.valueOf(row.get('Canonical_Term__c'));
            if (String.isNotBlank(original) && String.isNotBlank(canonical)) {
                mapping.put(original.trim().toLowerCase(), canonical.trim());
            }
        }
        return mapping;
    }

    private static String buildSummary(Contact con, String normalizedSkills, String cvText) {
        List<String> paragraphs = new List<String>();
        String name = String.isNotBlank(con.FirstName) ? con.FirstName : 'Candidate';
        String title = String.isNotBlank(con.Title) ? con.Title : 'professional';

        paragraphs.add(name + ' is a ' + title + ' with a profile showing relevant experience, practical capability, and clear career potential.');

        if (String.isNotBlank(normalizedSkills)) {
            paragraphs.add('Key strengths include ' + normalizedSkills + '. These skills give recruiters quick evidence for role matching and shortlisting.');
        } else {
            paragraphs.add('Key strengths should be confirmed during recruiter review because structured skills were not available from CV parsing.');
        }

        String location = String.join(new List<String>{
            blankToNull(con.MailingCity), blankToNull(con.MailingState), blankToNull(con.MailingCountry)
        }, ', ').replace(', ,', ',').replaceAll('^,\\s*|,\\s*$', '');
        if (String.isNotBlank(location)) {
            paragraphs.add('Candidate location signal is ' + location + ', useful for location-fit and availability checks.');
        } else {
            paragraphs.add('Location evidence is limited, so recruiter should confirm work location and remote preference.');
        }

        if (String.isNotBlank(cvText) && cvText.length() > 500) {
            paragraphs.add('CV content is rich enough for follow-up scoring, risk review, and protected candidate presentation.');
        } else {
            paragraphs.add('CV content is limited, so summary uses available parsed fields and should be enriched when fuller CV text is available.');
        }

        return String.join(paragraphs, '\n\n');
    }

    private static String buildFlags(String cvText) {
        List<String> flags = new List<String>();
        String text = String.isBlank(cvText) ? '' : cvText.toLowerCase();

        if (text.contains('gap') || text.contains('career break')) {
            flags.add('Possible employment gap: recruiter should verify dates.');
        }
        if (countOccurrences(text, 'present') >= 3 || countOccurrences(text, 'current') >= 3) {
            flags.add('Multiple recent roles mentioned: check job-change frequency.');
        }
        if (flags.isEmpty()) {
            flags.add('No major risk flags detected from available parsed CV text.');
        }
        return String.join(flags, '\n');
    }

    private static Decimal calculateMarketabilityScore(Contact con, String skills, String summary, String flags) {
        Decimal score = 0;
        Integer skillCount = parseSkillCount(skills);
        if (skillCount > 0) score += Math.min(30, skillCount * 4);

        Decimal years = decimalValue(con, 'Years_Experience__c');
        if (years != null && years > 0) score += Math.min(25, years * 5);

        Integer workHistoryCount = countWorkHistory(con.Id);
        Decimal completeness = 0;
        if (String.isNotBlank(summary)) completeness += 5;
        if (String.isNotBlank(con.Title)) completeness += 4;
        if (String.isNotBlank(con.Email)) completeness += 3;
        if (String.isNotBlank(con.MailingCity) || String.isNotBlank(con.MailingCountry)) completeness += 3;
        if (decimalValue(con, 'R_ATS__Minimum_Salary__c') != null || decimalValue(con, 'R_ATS__Maximum_Salary__c') != null) completeness += 3;
        if (workHistoryCount > 0) completeness += 2;
        score += Math.min(20, completeness);

        score += (String.isBlank(flags) || flags.contains('No major risk')) ? 15 : 7;

        Decimal roleClarity = 0;
        if (String.isNotBlank(con.Title)) roleClarity += 5;
        if (workHistoryCount > 0) roleClarity += 5;
        score += Math.min(10, roleClarity);

        if (score < 0) return 0;
        if (score > 100) return 100;
        return score;
    }

    private static Integer parseSkillCount(String skills) {
        if (String.isBlank(skills)) return 0;
        Integer count = 0;
        for (String part : skills.split('[,;\\n]+')) {
            if (String.isNotBlank(part)) count++;
        }
        return count;
    }

    private static Integer countWorkHistory(Id contactId) {
        if (contactId == null || !Schema.getGlobalDescribe().containsKey('Work_History__c')) return 0;
        try {
            return Database.countQuery('SELECT COUNT() FROM Work_History__c WHERE Contact__c = :contactId');
        } catch (Exception e) {
            return 0;
        }
    }

    private static void sendOnboardingInvitation(Id contactId, String email, String summary, String skills) {
        if (String.isBlank(email) || hasCompletedCareerIntent(contactId) || hasOnboardingEmail(contactId)) return;

        String subject = 'Continue your Blakeney career profile';
        String body = 'Hi,\n\nWe parsed your CV and found these useful signals:\n\n' +
            '- Skills: ' + (String.isBlank(skills) ? 'to be confirmed' : skills) + '\n' +
            '- Summary: ' + firstLine(summary) + '\n\n' +
            'Complete your Blakeney profile so we can match you with better opportunities.\n\n' +
            'Open Blakeney and continue onboarding.';

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ email });
        msg.setSubject(subject);
        msg.setPlainTextBody(body);
        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.Email[]{ msg }, false);

        if (results != null && !results.isEmpty() && results[0].isSuccess()) {
            logEmail(contactId, email, summary, skills);
        }
    }

    private static Boolean hasCompletedCareerIntent(Id contactId) {
        if (!Schema.getGlobalDescribe().containsKey('Career_Intent__c')) return false;
        Integer countRows = Database.countQuery(
            'SELECT COUNT() FROM Career_Intent__c WHERE Contact__c = :contactId'
        );
        return countRows > 0;
    }

    private static Boolean hasOnboardingEmail(Id contactId) {
        if (!Schema.getGlobalDescribe().containsKey('Email_Sent_Log__c')) return false;
        Integer countRows = Database.countQuery(
            'SELECT COUNT() FROM Email_Sent_Log__c WHERE Contact_Id__c = :contactId AND Email_Type__c = \'Onboarding_Invitation\''
        );
        return countRows > 0;
    }

    private static void logEmail(Id contactId, String email, String summary, String skills) {
        if (!Schema.getGlobalDescribe().containsKey('Email_Sent_Log__c')) return;

        SObject logRow = Schema.getGlobalDescribe().get('Email_Sent_Log__c').newSObject();
        logRow.put('Contact_Id__c', contactId);
        logRow.put('Email_Type__c', 'Onboarding_Invitation');
        logRow.put('Sent_Timestamp__c', System.now());
        logRow.put('Email_Template_Used__c', ONBOARDING_TEMPLATE);
        logRow.put('CV_Insights_Referenced__c', 'Skills: ' + skills + '\nSummary: ' + firstLine(summary));
        logRow.put('Link_Clicked__c', false);
        logRow.put('Recipient_Email__c', email);
        insert logRow;
    }

    private static void publishEnhancementEvent(Id contactId, Boolean summaryGenerated, Boolean skillsNormalized) {
        EventBus.publish(new CV_Enhancement_Complete__e(
            Contact_Id__c = String.valueOf(contactId),
            Summary_Generated__c = summaryGenerated,
            Skills_Normalized__c = skillsNormalized
        ));
    }

    private static void putIfFieldExists(SObject row, Schema.SObjectType typeRef, String fieldName, Object value) {
        if (typeRef.getDescribe().fields.getMap().containsKey(fieldName)) {
            row.put(fieldName, value);
        }
    }

    private static void putFirstExisting(SObject row, Schema.SObjectType typeRef, List<String> fieldNames, Object value) {
        Map<String, Schema.SObjectField> fields = typeRef.getDescribe().fields.getMap();
        for (String fieldName : fieldNames) {
            if (fields.containsKey(fieldName)) {
                row.put(fieldName, value);
                return;
            }
        }
    }

    private static void addIfFieldExists(Set<String> fields, Schema.SObjectType typeRef, String fieldName) {
        if (typeRef.getDescribe().fields.getMap().containsKey(fieldName)) {
            fields.add(fieldName);
        }
    }

    private static String value(SObject row, String fieldName) {
        try {
            Object val = row.get(fieldName);
            return val == null ? null : String.valueOf(val);
        } catch (Exception e) {
            return null;
        }
    }

    private static String stringValue(Object value) {
        if (value == null) return null;
        if (value instanceof List<Object>) {
            List<String> parts = new List<String>();
            for (Object item : (List<Object>) value) parts.add(String.valueOf(item));
            return String.join(parts, ', ');
        }
        return String.valueOf(value);
    }

    private static Decimal decimalFromObject(Object value) {
        if (value == null) return null;
        try {
            Decimal parsed = Decimal.valueOf(String.valueOf(value));
            if (parsed < 0) return 0;
            if (parsed > 100) return 100;
            return parsed.setScale(0);
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal decimalValue(SObject row, String fieldName) {
        try {
            Object val = row.get(fieldName);
            return val == null ? null : Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }

    private static String firstLine(String text) {
        if (String.isBlank(text)) return 'Profile ready for review.';
        String line = text.split('\\n')[0];
        return line.length() > 240 ? line.substring(0, 240) : line;
    }

    private static String blankToNull(String value) {
        return String.isBlank(value) ? null : value;
    }

    private static Integer countOccurrences(String haystack, String needle) {
        if (String.isBlank(haystack) || String.isBlank(needle)) return 0;
        Integer count = 0;
        Integer position = haystack.indexOf(needle);
        while (position >= 0) {
            count++;
            position = haystack.indexOf(needle, position + needle.length());
        }
        return count;
    }
}
