/*
----------------------------------------------------------------------------
IntentSaveQueueable.cls - CREATES NEW CAREER INTENT EVERY TIME
Stores complete 10-field career data in NEW record per session
----------------------------------------------------------------------------
*/
public class IntentSaveQueueable implements Queueable {
    
    private String contactId;
    private String sessionId;
    
    // Career Intent fields (4)
    private String shortTermGoal;
    private String mediumTermGoal;
    private String longTermGoal;
    private String aspirationalGoal;
    
    // Career Constraints fields (6)
    private String workLocation;
    private String remotePreference;
    private String minSalary;
    private String maxSalary;
    private String companySize;
    private String industryPreferences;
    
    // Constructor for complete career data
    public IntentSaveQueueable(String contactId, String sessionId,
                              String shortTermGoal, String mediumTermGoal,
                              String longTermGoal, String aspirationalGoal,
                              String workLocation, String remotePreference,
                              String minSalary, String maxSalary,
                              String companySize, String industryPreferences) {
        this.contactId = contactId;
        this.sessionId = sessionId;
        this.shortTermGoal = shortTermGoal;
        this.mediumTermGoal = mediumTermGoal;
        this.longTermGoal = longTermGoal;
        this.aspirationalGoal = aspirationalGoal;
        this.workLocation = workLocation;
        this.remotePreference = remotePreference;
        this.minSalary = minSalary;
        this.maxSalary = maxSalary;
        this.companySize = companySize;
        this.industryPreferences = industryPreferences;
    }
    
    // Legacy constructor for partial intent updates
    public IntentSaveQueueable(String contactId, String shortTermGoal, String mediumTermGoal,
                              String longTermGoal, String aspirationalGoal) {
        this.contactId = contactId;
        this.shortTermGoal = shortTermGoal;
        this.mediumTermGoal = mediumTermGoal;
        this.longTermGoal = longTermGoal;
        this.aspirationalGoal = aspirationalGoal;
    }
    
    public void execute(QueueableContext qc) {
        Savepoint sp = Database.setSavepoint();
        
        try {
            // ALWAYS CREATE NEW RECORD - No upsert, pure insert
            Career_Intent__c newIntent = new Career_Intent__c();
            newIntent.Contact__c = contactId;
            newIntent.Session_ID__c = sessionId;
            newIntent.Last_Check_In__c = DateTime.now();
            
            // Career Intent fields (from conversation answers)
            if (String.isNotBlank(shortTermGoal)) {
                newIntent.Short_Term_Goal__c = shortTermGoal;
            }
            if (String.isNotBlank(mediumTermGoal)) {
                newIntent.Medium_Term_Goal__c = mediumTermGoal;
            }
            if (String.isNotBlank(longTermGoal)) {
                newIntent.Long_Term_Goal__c = longTermGoal;
            }
            if (String.isNotBlank(aspirationalGoal)) {
                newIntent.Aspirational_Goal__c = aspirationalGoal;
            }
            
            // Career Constraints fields (from conversation answers)
            if (String.isNotBlank(workLocation)) {
                newIntent.Willing_to_Relocate__c = workLocation;
            }
            if (String.isNotBlank(remotePreference)) {
                newIntent.Short_Term_Remote__c = remotePreference;
            }
            if (String.isNotBlank(minSalary)) {
                newIntent.Min_Salary_Expactation__c = normalizeSalary(minSalary);
            }
            if (String.isNotBlank(maxSalary)) {
                newIntent.Max_Salary_Expactation__c = normalizeSalary(maxSalary);
            }
            if (String.isNotBlank(companySize)) {
                newIntent.Short_Term_Company_Size__c = companySize;
            }
            if (String.isNotBlank(industryPreferences)) {
                newIntent.Industry_Preferences__c = industryPreferences;
            }
            
            // Insert new record
            insert newIntent;
            
            System.debug('Created new Career Intent record: ' + newIntent.Id);
            
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, 'IntentSaveQueueable Error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
        }
    }
    
    // Normalize salary input
    private Integer normalizeSalary(String input) {
        if (String.isBlank(input)) {
            return null;
        }
        
        // Remove $ and commas
        String cleaned = input.replace('$', '').replace(',', '').trim();
        
        try {
            return Integer.valueOf(cleaned);
        } catch (Exception e) {
            return null;
        }
    }
}