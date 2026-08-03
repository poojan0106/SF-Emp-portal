public class AICVEnhancementService {
    private static final String ONBOARDING_TEMPLATE = 'Blakeney_Onboarding_Invitation_Static';
    private static final String ONBOARDING_CLICK_BASE_URL = System.Label.Blakeney_Onboarding_Click_Base_URL;
    private static Boolean lastClaudeEnhancementSucceeded = true;

    public static void enhanceContact(Id contactId) {
        enhanceContactInternal(contactId, true);
    }

    public static Boolean enhanceContactFromRetry(Id contactId) {
        return enhanceContactInternal(contactId, false);
    }

    private static Boolean enhanceContactInternal(Id contactId, Boolean enqueueRetryOnClaudeFailure) {
        if (contactId == null) return false;

        Long started = DateTime.now().getTime();
        lastClaudeEnhancementSucceeded = true;
        Contact con = fetchContact(contactId);
        if (con == null) return false;

        String originalSkills = value(con, 'R_ATS__Skills__c');
        String cvText = value(con, 'R_ATS__Text_CV__c');
        Map<String, Object> aiData = enhanceWithClaude(con, originalSkills, cvText, enqueueRetryOnClaudeFailure);
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
        syncCareerIntentSkills(con.Id, normalizedSkills);

        try {
            CandidateCVScoringService.scoreCampaignMembersForContact(con.Id);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'CampaignMember scoring failed after enhancement; Contact enhancement kept: ' + e.getMessage());
        }
        sendOnboardingInvitation(con.Id, con.Email, summary, normalizedSkills);
        publishEnhancementEvent(con.Id, String.isNotBlank(summary), String.isNotBlank(normalizedSkills));
        AIAPILogService.logSuccess(
            'CV Enhancement',
            con.Id,
            null,
            'Contact=' + con.Id,
            'Skills=' + normalizedSkills + '\nSummaryGenerated=' + String.isNotBlank(summary),
            Integer.valueOf(String.valueOf(DateTime.now().getTime() - started))
        );
        return lastClaudeEnhancementSucceeded;
    }

    public static void sendCandidateRegistrationInvitation(Id contactId, String email, String firstName) {
        if (contactId == null || String.isBlank(email) || hasOnboardingEmail(contactId)) return;

        String trackingToken = generateTrackingToken(contactId);
        String trackingUrl = buildTrackingUrl(trackingToken, contactId);
        String displayName = String.isNotBlank(firstName) ? firstName : 'there';
        String subject = 'Welcome to Blakeney';
        String body = 'Hi ' + displayName + ',\n\n' +
            'Welcome to Blakeney. Your candidate account is ready.\n\n' +
            'Complete or review your career profile here:\n' + trackingUrl + '\n\n' +
            'This helps Blakeney match you with better opportunities and career guidance.';

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ email });
        msg.setSubject(subject);
        msg.setPlainTextBody(body);
        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.Email[]{ msg }, false);

        if (results != null && !results.isEmpty() && results[0].isSuccess()) {
            logEmail(contactId, email, 'Candidate registration onboarding invitation', '', trackingToken, trackingUrl);
        }
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

    private static void syncCareerIntentSkills(Id contactId, String skillsText) {
        if (contactId == null || String.isBlank(skillsText) || !Schema.getGlobalDescribe().containsKey('Career_Intent__c')) return;

        try {
            List<Career_Intent__c> intents = [
                SELECT Id, Skills__c
                FROM Career_Intent__c
                WHERE Contact__c = :contactId OR Candidate__c = :contactId
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            Career_Intent__c intent = intents.isEmpty()
                ? new Career_Intent__c(Contact__c = contactId, Candidate__c = contactId)
                : intents[0];
            String normalizedSkills = normalizeSkills(skillsText);
            if (String.isBlank(normalizedSkills) || intent.Skills__c == normalizedSkills) return;

            intent.Skills__c = normalizedSkills;
            if (intent.Id == null) insert intent;
            else update intent;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Unable to sync Career Intent skills: ' + e.getMessage());
        }
    }

    private static Map<String, Object> enhanceWithClaude(Contact con, String skills, String cvText, Boolean enqueueRetryOnFailure) {
        if (String.isBlank(cvText) && String.isBlank(skills)) return new Map<String, Object>();
        if (Test.isRunningTest()) return new Map<String, Object>();
        String prompt =
            'Analyze this candidate CV/profile. Return ONLY valid JSON with keys: ' +
            'skills (comma-separated canonical skills), summary (3-4 professional paragraphs), ' +
            'flags (newline-separated risks: employment gaps over 6 months, frequent job changes, qualification mismatches, or \"No major risk flags detected\"), ' +
            'marketabilityScore (0-100). Use Australian recruitment terminology. No markdown.';
        String sourcePayload =
            'Name: ' + con.FirstName + ' ' + con.LastName +
                '\nTitle: ' + con.Title +
                '\nParsed skills: ' + skills +
                '\nCV Text:\n' + cvText;
        Long started = DateTime.now().getTime();
        try {
            Map<String, Object> result = ClaudeAPIService.extractStructuredData(
                sourcePayload,
                prompt
            );
            lastClaudeEnhancementSucceeded = !result.isEmpty();
            if (result.isEmpty()) {
                String error = 'Claude returned no structured enhancement data.';
                AIAPILogService.logFailure(
                    'CV Enhancement',
                    con.Id,
                    null,
                    sourcePayload,
                    error,
                    Integer.valueOf(String.valueOf(DateTime.now().getTime() - started))
                );
                // Retry disabled per current requirement. Re-enable to queue Claude fallback failures.
                // if (enqueueRetryOnFailure) {
                //     AIRetryService.enqueue(con.Id, null, 'CV Enhancement', sourcePayload, error);
                // }
            }
            return result;
        } catch (Exception e) {
            lastClaudeEnhancementSucceeded = false;
            System.debug(LoggingLevel.WARN, 'Claude enhancement failed; static fallback used: ' + e.getMessage());
            AIAPILogService.logFailure(
                'CV Enhancement',
                con.Id,
                null,
                sourcePayload,
                e.getMessage(),
                Integer.valueOf(String.valueOf(DateTime.now().getTime() - started))
            );
            // Retry disabled per current requirement. Re-enable to queue Claude exceptions.
            // if (enqueueRetryOnFailure) {
            //     AIRetryService.enqueue(con.Id, null, 'CV Enhancement', sourcePayload, e.getMessage());
            // }
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
        if (text.contains('lorem ipsum')) {
            flags.add('Placeholder CV text detected: recruiter should request a real CV before final decision.');
        }

        List<YearRange> ranges = extractYearRanges(text);
        if (!ranges.isEmpty()) {
            Integer currentYear = Date.today().year();
            Integer recentRoleCount = 0;
            ranges.sort();
            for (Integer i = 0; i < ranges.size(); i++) {
                YearRange range = ranges[i];
                if (range.startYear >= currentYear - 3 || range.endYear >= currentYear - 3) {
                    recentRoleCount++;
                }
                if (range.endYear > currentYear + 1) {
                    flags.add('Future-dated work or education range detected: verify CV dates.');
                }
                if (i > 0) {
                    YearRange previous = ranges[i - 1];
                    if (range.startYear - previous.endYear > 1) {
                        flags.add('Possible employment gap over 6 months between ' + previous.endYear + ' and ' + range.startYear + '.');
                    }
                }
            }
            if (recentRoleCount >= 3) {
                flags.add('Frequent job changes: 3 or more roles appear within the last 3 years.');
            }
        } else if (countOccurrences(text, 'present') >= 3 || countOccurrences(text, 'current') >= 3) {
            flags.add('Multiple current/recent roles mentioned: check job-change frequency.');
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

        String trackingToken = generateTrackingToken(contactId);
        String trackingUrl = buildTrackingUrl(trackingToken, contactId);
        String subject = 'Continue your Blakeney career profile';
        String body = 'Hi,\n\nWe parsed your CV and found these useful signals:\n\n' +
            '- Skills: ' + (String.isBlank(skills) ? 'to be confirmed' : skills) + '\n' +
            '- Summary: ' + firstLine(summary) + '\n\n' +
            'Complete your Blakeney profile so we can match you with better opportunities.\n\n' +
            'Open Blakeney and continue onboarding:\n' + trackingUrl;

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ email });
        msg.setSubject(subject);
        msg.setPlainTextBody(body);
        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.Email[]{ msg }, false);

        if (results != null && !results.isEmpty() && results[0].isSuccess()) {
            logEmail(contactId, email, summary, skills, trackingToken, trackingUrl);
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

    private static void logEmail(Id contactId, String email, String summary, String skills, String trackingToken, String trackingUrl) {
        if (!Schema.getGlobalDescribe().containsKey('Email_Sent_Log__c')) return;

        SObject logRow = Schema.getGlobalDescribe().get('Email_Sent_Log__c').newSObject();
        logRow.put('Contact_Id__c', contactId);
        logRow.put('Email_Type__c', 'Onboarding_Invitation');
        logRow.put('Sent_Timestamp__c', System.now());
        logRow.put('Email_Template_Used__c', ONBOARDING_TEMPLATE);
        logRow.put('CV_Insights_Referenced__c', 'Skills: ' + skills + '\nSummary: ' + firstLine(summary));
        logRow.put('Link_Clicked__c', false);
        logRow.put('Recipient_Email__c', email);
        putIfFieldExists(logRow, Schema.getGlobalDescribe().get('Email_Sent_Log__c'), 'Tracking_Token__c', trackingToken);
        putIfFieldExists(logRow, Schema.getGlobalDescribe().get('Email_Sent_Log__c'), 'Tracking_Url__c', trackingUrl);
        insert logRow;
    }

    private static String generateTrackingToken(Id contactId) {
        String seed = String.valueOf(contactId) + ':' + String.valueOf(System.now().getTime()) + ':' + String.valueOf(Crypto.getRandomLong());
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(seed))).substring(0, 40);
    }

    private static String buildTrackingUrl(String trackingToken, Id contactId) {
        return ONBOARDING_CLICK_BASE_URL +
            '?token=' + EncodingUtil.urlEncode(trackingToken, 'UTF-8') +
            '&contactId=' + EncodingUtil.urlEncode(String.valueOf(contactId), 'UTF-8');
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

    private class YearRange implements Comparable {
        Integer startYear;
        Integer endYear;

        YearRange(Integer startYear, Integer endYear) {
            this.startYear = startYear;
            this.endYear = endYear;
        }

        public Integer compareTo(Object other) {
            YearRange rhs = (YearRange) other;
            if (this.startYear == rhs.startYear) return this.endYear - rhs.endYear;
            return this.startYear - rhs.startYear;
        }
    }

    private static List<YearRange> extractYearRanges(String text) {
        List<YearRange> ranges = new List<YearRange>();
        if (String.isBlank(text)) return ranges;

        Pattern rangePattern = Pattern.compile('((?:19|20)\\d{2})\\s*[-\\u2013\\u2014]\\s*((?:19|20)\\d{2}|present|current)');
        Matcher matcher = rangePattern.matcher(text);
        Integer currentYear = Date.today().year();

        while (matcher.find()) {
            Integer startYear = safeYear(matcher.group(1), currentYear);
            Integer endYear = safeYear(matcher.group(2), currentYear);
            if (startYear != null && endYear != null && endYear >= startYear) {
                ranges.add(new YearRange(startYear, endYear));
            }
        }
        return ranges;
    }

    private static Integer safeYear(String value, Integer currentYear) {
        if (String.isBlank(value)) return null;
        String cleaned = value.trim().toLowerCase();
        if (cleaned == 'present' || cleaned == 'current') return currentYear;
        try {
            return Integer.valueOf(cleaned);
        } catch (Exception e) {
            return null;
        }
    }
}
