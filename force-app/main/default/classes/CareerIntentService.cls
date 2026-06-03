/*
----------------------------------------------------------------------------
CareerIntentService.cls - Intent Query & Utility Methods
UPDATED: Deprecated extraction method (now handled by ChatDMLQueueable)
----------------------------------------------------------------------------
*/
public with sharing class CareerIntentService {
    
    // GET: Retrieve LATEST career intent for contact (used by API and resume logic)
    public static Career_Intent__c getCareerIntent(String contactId) {
        List<Career_Intent__c> intents = [
            SELECT Id, Name, Contact__c, Session_ID__c,
                   Short_Term_Goal__c, Medium_Term_Goal__c,
                   Long_Term_Goal__c, Aspirational_Goal__c, 
                   Last_Check_In__c, Check_In_Opt_Out__c, 
                   Inactive_Since__c, Current_State_Summary__c,
                   Gap_Analysis__c, CreatedDate, LastModifiedDate,
                   Willing_to_Relocate__c, Short_Term_Remote__c,
                   Min_Salary_Expactation__c, Max_Salary_Expactation__c,
                   Short_Term_Company_Size__c, Industry_Preferences__c,
                   Role_Title__c
            FROM Career_Intent__c 
            WHERE Contact__c = :contactId 
            ORDER BY CreatedDate DESC 
            LIMIT 1
        ];
        return intents.isEmpty() ? null : intents[0];
    }
    
    // GET: Retrieve ALL career intents for contact (for history/analytics)
    public static List<Career_Intent__c> getAllCareerIntents(String contactId) {
        return [
            SELECT Id, Name, Contact__c, Session_ID__c,
                   Short_Term_Goal__c, Medium_Term_Goal__c,
                   Long_Term_Goal__c, Aspirational_Goal__c,
                   Willing_to_Relocate__c, Short_Term_Remote__c,
                   Min_Salary_Expactation__c, Max_Salary_Expactation__c,
                   Short_Term_Company_Size__c, Industry_Preferences__c,
                   Role_Title__c, Last_Check_In__c,
                   CreatedDate, LastModifiedDate
            FROM Career_Intent__c 
            WHERE Contact__c = :contactId 
            ORDER BY CreatedDate DESC
        ];
    }
    
    // GET: Retrieve intent for specific session
    public static Career_Intent__c getSessionIntent(String contactId, String sessionId) {
        List<Career_Intent__c> intents = [
            SELECT Id, Name, Contact__c, Session_ID__c,
                   Short_Term_Goal__c, Medium_Term_Goal__c,
                   Long_Term_Goal__c, Aspirational_Goal__c,
                   Willing_to_Relocate__c, Short_Term_Remote__c,
                   Min_Salary_Expactation__c, Max_Salary_Expactation__c,
                   Short_Term_Company_Size__c, Industry_Preferences__c,
                   Role_Title__c, Last_Check_In__c,
                   CreatedDate, LastModifiedDate
            FROM Career_Intent__c 
            WHERE Contact__c = :contactId 
            ORDER BY CreatedDate DESC
            // AND Session_ID__c = :sessionId
            LIMIT 1
        ];
        return intents.isEmpty() ? null : intents[0];
    }
    
    
    // Calculate completeness score (0-100) based on filled fields
    public static Integer calculateCompletenessScore(String contactId) {
        Career_Intent__c intent = getCareerIntent(contactId);
        if (intent == null) return 0;
        
        Integer score = 0;
        Integer fieldsTotal = 11;  // Total fields we collect
        
        if (String.isNotBlank(intent.Short_Term_Goal__c)) score += 9;
        if (String.isNotBlank(intent.Medium_Term_Goal__c)) score += 9;
        if (String.isNotBlank(intent.Long_Term_Goal__c)) score += 9;
        if (String.isNotBlank(intent.Aspirational_Goal__c)) score += 9;
        if (String.isNotBlank(intent.Willing_to_Relocate__c)) score += 9;
        if (String.isNotBlank(intent.Short_Term_Remote__c)) score += 9;
        if (intent.Min_Salary_Expactation__c != null) score += 10;
        if (intent.Max_Salary_Expactation__c != null) score += 9;
        if (String.isNotBlank(intent.Short_Term_Company_Size__c)) score += 9;
        if (String.isNotBlank(intent.Industry_Preferences__c)) score += 9;
        if (String.isNotBlank(intent.Role_Title__c)) score += 9;
        
        return score;
    }
    
    // Calculate completeness for specific session
    public static Integer calculateSessionCompletenessScore(String contactId, String sessionId) {
        Career_Intent__c intent = getSessionIntent(contactId, sessionId);
        if (intent == null) return 0;
        
        Integer score = 0;
        
        if (String.isNotBlank(intent.Short_Term_Goal__c)) score += 9;
        if (String.isNotBlank(intent.Medium_Term_Goal__c)) score += 9;
        if (String.isNotBlank(intent.Long_Term_Goal__c)) score += 9;
        if (String.isNotBlank(intent.Aspirational_Goal__c)) score += 9;
        if (String.isNotBlank(intent.Willing_to_Relocate__c)) score += 9;
        if (String.isNotBlank(intent.Short_Term_Remote__c)) score += 9;
        if (intent.Min_Salary_Expactation__c != null) score += 10;
        if (intent.Max_Salary_Expactation__c != null) score += 9;
        if (String.isNotBlank(intent.Short_Term_Company_Size__c)) score += 9;
        if (String.isNotBlank(intent.Industry_Preferences__c)) score += 9;
        if (String.isNotBlank(intent.Role_Title__c)) score += 9;
        
        return score;
    }
    
    // Get candidates due for check-in (for scheduled batch jobs)
    public static List<Career_Intent__c> getCandidatesDueForCheckIn() {
        Date thirtyDaysAgo = Date.today().addDays(-30);
        
        // Get latest intent per contact (subquery approach)
        List<Career_Intent__c> recentIntents = [
            SELECT Id, Contact__c, Contact__r.FirstName, 
                   Contact__r.Email, Last_Check_In__c,
                   Session_ID__c, CreatedDate
            FROM Career_Intent__c
            WHERE Check_In_Opt_Out__c = false
            AND Inactive_Since__c = null
            AND (Last_Check_In__c = null OR Last_Check_In__c < :thirtyDaysAgo)
            ORDER BY Contact__c, CreatedDate DESC
        ];
        
        // Deduplicate to one record per contact (latest)
        Map<Id, Career_Intent__c> latestPerContact = new Map<Id, Career_Intent__c>();
        for (Career_Intent__c intent : recentIntents) {
            if (!latestPerContact.containsKey(intent.Contact__c)) {
                latestPerContact.put(intent.Contact__c, intent);
            }
        }
        
        return latestPerContact.values();
    }
    
    // Compare two intent records (useful for tracking changes)
    public static Map<String, Boolean> compareIntents(Career_Intent__c oldIntent, Career_Intent__c newIntent) {
        Map<String, Boolean> changes = new Map<String, Boolean>();
        
        if (oldIntent == null || newIntent == null) {
            return changes;
        }
        
        changes.put('shortTermChanged', oldIntent.Short_Term_Goal__c != newIntent.Short_Term_Goal__c);
        changes.put('mediumTermChanged', oldIntent.Medium_Term_Goal__c != newIntent.Medium_Term_Goal__c);
        changes.put('longTermChanged', oldIntent.Long_Term_Goal__c != newIntent.Long_Term_Goal__c);
        changes.put('aspirationalChanged', oldIntent.Aspirational_Goal__c != newIntent.Aspirational_Goal__c);
        changes.put('locationChanged', oldIntent.Willing_to_Relocate__c != newIntent.Willing_to_Relocate__c);
        changes.put('remoteChanged', oldIntent.Short_Term_Remote__c != newIntent.Short_Term_Remote__c);
        changes.put('minSalaryChanged', oldIntent.Min_Salary_Expactation__c != newIntent.Min_Salary_Expactation__c);
        changes.put('maxSalaryChanged', oldIntent.Max_Salary_Expactation__c != newIntent.Max_Salary_Expactation__c);
        changes.put('companySizeChanged', oldIntent.Short_Term_Company_Size__c != newIntent.Short_Term_Company_Size__c);
        changes.put('industryChanged', oldIntent.Industry_Preferences__c != newIntent.Industry_Preferences__c);
        changes.put('roleChanged', oldIntent.Role_Title__c != newIntent.Role_Title__c);
        
        return changes;
    }
    
    // Get career progression summary (all intents over time)
    public static List<Map<String, Object>> getCareerProgression(String contactId) {
        List<Map<String, Object>> progression = new List<Map<String, Object>>();
        
        List<Career_Intent__c> intents = getAllCareerIntents(contactId);
        
        for (Career_Intent__c intent : intents) {
            Map<String, Object> snapshot = new Map<String, Object>();
            snapshot.put('sessionId', intent.Session_ID__c);
            snapshot.put('createdDate', intent.CreatedDate);
            snapshot.put('shortTerm', intent.Short_Term_Goal__c);
            snapshot.put('mediumTerm', intent.Medium_Term_Goal__c);
            snapshot.put('longTerm', intent.Long_Term_Goal__c);
            snapshot.put('aspirational', intent.Aspirational_Goal__c);
            snapshot.put('completeness', calculateSessionCompletenessScore(contactId, intent.Session_ID__c));
            
            progression.add(snapshot);
        }
        
        return progression;
    }
}