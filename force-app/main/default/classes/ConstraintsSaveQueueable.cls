/*
----------------------------------------------------------------------------
4.6 ConstraintsSaveQueueable.cls - ASYNC Constraints Save
Handles saving career constraints in background (no DML in API)
----------------------------------------------------------------------------
*/
public class ConstraintsSaveQueueable implements Queueable {
    
    private String contactId;
    private String preferredLocations;
    private String willingToRelocate;
    private String remoteWorkRequirement;
    private Decimal minSalary;
    private Decimal maxSalary;
    private String compensationType;
    private Integer maxHoursPerWeek;
    private String flexibilityImportance;
    private String travelWillingness;
    private String companySizePreference;
    private String industryPreferences;
    private String industryExclusions;
    private String riskTolerance;
    private String culturePreferences;
    private String dealBreakers;
  //  private Integer workLifeBalancePriority;
    
    // Constructor from request object
    public ConstraintsSaveQueueable(BlakeneyRestAPI.CareerConstraintsRequest req) {
        this.contactId = req.contactId;
        this.preferredLocations = req.preferredLocations;
        this.willingToRelocate = req.willingToRelocate;
        this.remoteWorkRequirement = req.remoteWorkRequirement;
        this.minSalary = req.minSalary;
        this.maxSalary = req.maxSalary;
        this.compensationType = req.compensationType;
        this.maxHoursPerWeek = req.maxHoursPerWeek;
        this.flexibilityImportance = req.flexibilityImportance;
        this.travelWillingness = req.travelWillingness;
        this.companySizePreference = req.companySizePreference;
        this.industryPreferences = req.industryPreferences;
        this.industryExclusions = req.industryExclusions;
        this.riskTolerance = req.riskTolerance;
        this.culturePreferences = req.culturePreferences;
        this.dealBreakers = req.dealBreakers;
    //    this.workLifeBalancePriority = req.workLifeBalancePriority;
    }
    
    public void execute(QueueableContext qc) {
        Savepoint sp = Database.setSavepoint();
        
        try {
            // Check for existing constraints record
            List<Career_Constraints__c> existing = [
                SELECT Id FROM Career_Constraints__c 
                WHERE Contact__c = :contactId 
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            
            Career_Constraints__c constraints;
            if (!existing.isEmpty()) {
                constraints = existing[0];
            } else {
                constraints = new Career_Constraints__c();
                constraints.Contact__c = contactId;
            }
            
            // Update only non-null fields (merge approach)
            if (preferredLocations != null) constraints.Preferred_Locations__c = preferredLocations;
            if (willingToRelocate != null) constraints.Willing_to_Relocate__c = willingToRelocate;
            if (remoteWorkRequirement != null) constraints.Remote_Work_Requirement__c = remoteWorkRequirement;
            if (minSalary != null) constraints.Min_Salary__c = minSalary;
            if (maxSalary != null) constraints.Max_Salary__c = maxSalary;
            if (compensationType != null) constraints.Compensation_Type__c = compensationType;
            if (maxHoursPerWeek != null) constraints.Max_Hours_Per_Week__c = maxHoursPerWeek;
            if (flexibilityImportance != null) constraints.Flexibility_Importance__c = flexibilityImportance;
            if (travelWillingness != null) constraints.Travel_Willingness__c = travelWillingness;
            if (companySizePreference != null) constraints.Company_Size_Preference__c = companySizePreference;
            if (industryPreferences != null) constraints.Industry_Preferences__c = industryPreferences;
            if (industryExclusions != null) constraints.Industry_Exclusions__c = industryExclusions;
            if (riskTolerance != null) constraints.Risk_Tolerance__c = riskTolerance;
            if (culturePreferences != null) constraints.Culture_Preferences__c = culturePreferences;
            if (dealBreakers != null) constraints.Deal_Breakers__c = dealBreakers;
          //  if (workLifeBalancePriority != null) constraints.Work_Life_Balance_Priority__c = workLifeBalancePriority;
            
            // Validate salary range (swap if min > max)
            if (constraints.Min_Salary__c != null && constraints.Max_Salary__c != null) {
                if (constraints.Min_Salary__c > constraints.Max_Salary__c) {
                    Decimal temp = constraints.Min_Salary__c;
                    constraints.Min_Salary__c = constraints.Max_Salary__c;
                    constraints.Max_Salary__c = temp;
                }
            }
            
            upsert constraints;
            
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, 'ConstraintsSaveQueueable Error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
        }
    }
}