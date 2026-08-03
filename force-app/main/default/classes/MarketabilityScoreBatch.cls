public with sharing class MarketabilityScoreBatch implements Database.Batchable<SObject>, Schedulable {
    public Database.QueryLocator start(Database.BatchableContext context) {
        Set<String> fields = new Set<String>{
            'Id', 'Email', 'Title', 'MailingCity', 'MailingCountry'
        };
        addIfFieldExists(fields, Contact.SObjectType, 'R_ATS__Skills__c');
        addIfFieldExists(fields, Contact.SObjectType, 'R_ATS__Candidate_Summary__c');
        addIfFieldExists(fields, Contact.SObjectType, 'Candidate_Summary__c');
        addIfFieldExists(fields, Contact.SObjectType, 'R_ATS__Candidate_Flags__c');
        addIfFieldExists(fields, Contact.SObjectType, 'Candidate_Flags__c');
        addIfFieldExists(fields, Contact.SObjectType, 'Years_Experience__c');
        addIfFieldExists(fields, Contact.SObjectType, 'R_ATS__Minimum_Salary__c');
        addIfFieldExists(fields, Contact.SObjectType, 'R_ATS__Maximum_Salary__c');
        addIfFieldExists(fields, Contact.SObjectType, 'Profile_Completeness__c');

        String soql = 'SELECT ' + String.join(new List<String>(fields), ',') +
            ' FROM Contact WHERE IsDeleted = false';
        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext context, List<Contact> scope) {
        Set<Id> contactIds = new Set<Id>();
        for (Contact con : scope) contactIds.add(con.Id);

        Map<Id, Integer> workCounts = countByContact('Work_History__c', contactIds);
        Map<Id, Integer> educationCounts = countByContact('Education__c', contactIds);
        Map<Id, Integer> certificationCounts = countByContact('Certification__c', contactIds);

        List<Contact> updates = new List<Contact>();
        for (Contact con : scope) {
            Decimal score = calculate(con, workCounts.get(con.Id), educationCounts.get(con.Id), certificationCounts.get(con.Id));
            Contact updateContact = new Contact(Id = con.Id);
            if (Contact.SObjectType.getDescribe().fields.getMap().containsKey('Marketability_Score__c')) {
                updateContact.put('Marketability_Score__c', score);
                updates.add(updateContact);
            }
        }
        if (!updates.isEmpty()) update updates;
    }

    public void finish(Database.BatchableContext context) {}

    public void execute(SchedulableContext context) {
        Database.executeBatch(new MarketabilityScoreBatch(), 100);
    }

    private static Decimal calculate(Contact con, Integer workCount, Integer educationCount, Integer certificationCount) {
        Decimal score = 0;
        Integer skillCount = parseSkillCount(value(con, 'R_ATS__Skills__c'));
        score += Math.min(30, skillCount * 4);

        Decimal years = decimalValue(con, 'Years_Experience__c');
        if (years != null && years > 0) score += Math.min(25, years * 5);

        Decimal completeness = 0;
        String summary = firstValue(con, new List<String>{ 'R_ATS__Candidate_Summary__c', 'Candidate_Summary__c' });
        if (String.isNotBlank(summary)) completeness += 5;
        if (String.isNotBlank(con.Title)) completeness += 4;
        if (String.isNotBlank(con.Email)) completeness += 3;
        if (String.isNotBlank(con.MailingCity) || String.isNotBlank(con.MailingCountry)) completeness += 3;
        if (decimalValue(con, 'R_ATS__Minimum_Salary__c') != null || decimalValue(con, 'R_ATS__Maximum_Salary__c') != null) completeness += 3;
        if (safeCount(workCount) > 0) completeness += 2;
        if (safeCount(educationCount) > 0) completeness += 1;
        if (safeCount(certificationCount) > 0) completeness += 1;
        Decimal profileCompleteness = decimalValue(con, 'Profile_Completeness__c');
        if (profileCompleteness != null) completeness += Math.min(2, profileCompleteness / 50);
        score += Math.min(20, completeness);

        String flags = firstValue(con, new List<String>{ 'R_ATS__Candidate_Flags__c', 'Candidate_Flags__c' });
        score += (String.isBlank(flags) || flags.contains('No major risk')) ? 15 : 7;

        Decimal roleClarity = 0;
        if (String.isNotBlank(con.Title)) roleClarity += 5;
        if (safeCount(workCount) > 0) roleClarity += 5;
        score += Math.min(10, roleClarity);

        if (score < 0) score = 0;
        if (score > 100) score = 100;
        return score.setScale(0);
    }

    private static Map<Id, Integer> countByContact(String objectName, Set<Id> contactIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (contactIds == null || contactIds.isEmpty() || !Schema.getGlobalDescribe().containsKey(objectName)) return counts;
        try {
            for (AggregateResult result : Database.query(
                'SELECT Contact__c contactId, COUNT(Id) total FROM ' + objectName +
                ' WHERE Contact__c IN :contactIds GROUP BY Contact__c'
            )) {
                counts.put((Id) result.get('contactId'), (Integer) result.get('total'));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Marketability count skipped for ' + objectName + ': ' + e.getMessage());
        }
        return counts;
    }

    private static Integer safeCount(Integer value) {
        return value == null ? 0 : value;
    }

    private static Integer parseSkillCount(String skills) {
        if (String.isBlank(skills)) return 0;
        Integer count = 0;
        for (String part : skills.split('[,;\\n]+')) {
            if (String.isNotBlank(part)) count++;
        }
        return count;
    }

    private static void addIfFieldExists(Set<String> fields, Schema.SObjectType typeRef, String fieldName) {
        if (typeRef.getDescribe().fields.getMap().containsKey(fieldName)) fields.add(fieldName);
    }

    private static String firstValue(SObject row, List<String> fieldNames) {
        for (String fieldName : fieldNames) {
            String text = value(row, fieldName);
            if (String.isNotBlank(text)) return text;
        }
        return null;
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
            return val == null ? null : Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }
}
