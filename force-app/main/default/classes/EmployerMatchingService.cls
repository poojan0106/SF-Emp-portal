/**
 * ═══════════════════════════════════════════════════════════════════════════
 * FILE 2: EmployerMatchingService.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Matches employers to candidates based on preferences
 * 
 * TASKS COVERED:
 *   - US-041-BE-011: Create employer matching algorithm
 *   - US-041-BE-012: Build "already swiped" exclusion logic
 * 
 * MATCHING CRITERIA:
 *   - Exclude employers swiped in last 6 months
 *   - Filter by candidate's industry preferences
 *   - Filter by location (same state or remote-friendly)
 *   - Order by Hiring Intent Score (employers actively hiring)
 * ═══════════════════════════════════════════════════════════════════════════
 */
public with sharing class EmployerMatchingService {
    
    /** Days before a swiped employer can reappear */
    private static final Integer SWIPE_COOLDOWN_DAYS = 180;
    
    /**
     * Main entry point: Gets matching employers for a candidate.
     * 
     * ALGORITHM:
     * 1. Get candidate preferences from Career_Intent__c
     * 2. Get excluded employer IDs (already swiped)
     * 3. Build dynamic query with filters
     * 4. Execute query and transform results
     * 
     * @param candidateId Contact Id of the candidate
     * @param batchSize Number of employers to return
     * @return List of EmployerCard objects for UI display
     */
    public static List<SwipeController.EmployerCard> getMatchingEmployers(
        Id candidateId, 
        Integer batchSize
    ) {
        // Step 1: Get candidate with their preferences
        Contact candidate = getCandidateWithPreferences(candidateId);
        
        // Step 2: Get employers to exclude (TASK BE-012)
        Set<Id> excludedEmployerIds = getExcludedEmployerIds(candidateId);
        
        // Step 3: Query matching employers
        List<Account> employers = queryMatchingEmployers(candidate, excludedEmployerIds, batchSize);
        
        // Step 4: Transform to EmployerCard objects
        return transformToEmployerCards(employers, candidate);
    }
    
    /**
     * Queries the candidate with their active career intent.
     */
    private static Contact getCandidateWithPreferences(Id candidateId) {
        return [
            SELECT Id, 
                   MailingCity, 
                   MailingState, 
                   MailingCountry,
                   Preferred_Industries__c,
                   Preferred_Company_Size__c,
                   R_ATS__Minimum_Salary__c,
                   Remote_Preference__c,
                   // Get active career intent (subquery)
                   (SELECT Id, 
                           Target_Role__c, 
                           Short_Term_Industry__c,
                           Short_Term_Location__c,
                           Min_Salary_Expactation__c
                    FROM Career_Intents__r
                    //WHERE Is_Active__c = true
                    ORDER BY CreatedDate DESC
                    LIMIT 1)
            FROM Contact
            WHERE Id = :candidateId
            LIMIT 1
        ];
    }
    
    /**
     * TASK US-041-BE-012: Gets IDs of employers the candidate has already swiped.
     * 
     * BUSINESS RULE:
     * - Employers swiped in last 6 months are excluded
     * - Undone swipes don't count (Is_Undone__c = true)
     * 
     * @param candidateId Contact Id of the candidate
     * @return Set of Account IDs to exclude
     */
    private static Set<Id> getExcludedEmployerIds(Id candidateId) {
        Set<Id> excludedIds = new Set<Id>();
        
        // Calculate cooldown date (6 months ago)
        Date cooldownDate = Date.today().addDays(-SWIPE_COOLDOWN_DAYS);
        
        // Query all non-undone swipes within cooldown period
        for (Swipe_Event__c swipe : [
            SELECT Employers__c
            FROM Swipe_Event__c
            WHERE Candidate__c = :candidateId
            AND Is_Undone__c = false
            AND Timestamp__c >= :cooldownDate
        ]) {
            excludedIds.add(swipe.Employers__c);
        }
        
        return excludedIds;
    }
    
    /**
     * TASK US-041-BE-011: Builds and executes employer matching query.
     * 
     * FILTERS APPLIED:
     * 1. RecordType = Employer
     * 2. Is_Active__c = true
     * 3. Profile_Completeness__c >= 50 (data quality)
     * 4. NOT IN excluded IDs (already swiped)
     * 5. Industry matches preference (if specified)
     * 6. Location matches OR has remote positions
     * 
     * ORDERING:
     * - Hiring_Intent_Score__c DESC (actively hiring first)
     * - Overall_Sentiment_Score__c DESC (well-reviewed second)
     */
    private static List<Account> queryMatchingEmployers(
        Contact candidate, 
        Set<Id> excludedIds, 
        Integer batchSize
    ) {
        // Build WHERE conditions
        String whereClause = 
            // 'RecordType.DeveloperName = \'Employer\' ' +
                            'Is_Active__c = true ' +
                            'AND Profile_Completeness__c >= 50 ' +
                            'AND Id IN (SELECT Employer__c FROM Campaign WHERE Employer__c != null AND IsActive = true AND Status = \'Active\')';
        
        // Exclude already swiped employers
        if (!excludedIds.isEmpty()) {
            whereClause += ' AND Id NOT IN :excludedIds';
        }
        
        // Filter by location (same state or remote-friendly)
        if (String.isNotBlank(candidate.MailingState)) {
            String candidateState = candidate.MailingState;
            whereClause += ' AND (BillingState = :candidateState OR Has_Remote_Positions__c = true)';
        }
        
        // Build full query
        String query = 
            'SELECT Id, Name, Industry, Employee_Count__c, Description, ' +
            'Logo_URL__c, Company_Culture__c, Company_Values__c, Company_Size__c, Typical_Roles__c, ' +
            'Remote_Work_Policy__c, Why_Join__c, ' +
            'Overall_Sentiment_Score__c, Salary_Range_Min__c, Salary_Range_Max__c, ' +
            'Hiring_Intent_Score__c, Culture_Highlights__c, Has_Remote_Positions__c, ' +
            'BillingCity, BillingState ' +
            'FROM Account ' +
            'WHERE ' + whereClause + ' ' +
           // 'ORDER BY Hiring_Intent_Score__c DESC NULLS LAST, ' +
          //  'Overall_Sentiment_Score__c DESC NULLS LAST ' +
            'LIMIT :batchSize';
        
        // Bind variables for dynamic query
        String candidateState = candidate.MailingState;
        
        return Database.query(query);
    }
    
    /**
     * Transforms Account records to EmployerCard DTOs for API response.
     */
    private static List<SwipeController.EmployerCard> transformToEmployerCards(
        List<Account> employers,
        Contact candidate
    ) {
        List<SwipeController.EmployerCard> cards = new List<SwipeController.EmployerCard>();
        
        for (Account emp : employers) {
            SwipeController.EmployerCard card = new SwipeController.EmployerCard();
            
            // Basic info
            card.employerId = emp.Id;
            card.name = emp.Name;
            card.logoUrl = emp.Logo_URL__c;
            card.industry = emp.Industry;
            card.description = emp.Description;
            card.companyCulture = emp.Company_Culture__c;
            card.companySize = emp.Company_Size__c;
            card.remoteWorkPolicy = emp.Remote_Work_Policy__c;
            card.whyJoin = emp.Why_Join__c;
            
            // Formatted fields
            card.employeeCount = formatEmployeeCount(emp.Employee_Count__c);
            card.salaryRange = formatSalaryRange(emp.Salary_Range_Min__c, emp.Salary_Range_Max__c);
            
            // JSON array fields
            card.highlights = parseJsonArray(emp.Culture_Highlights__c);
            card.values = parseJsonArray(emp.Company_Values__c);
            
            // Other fields
            card.typicalRoles = emp.Typical_Roles__c;
            card.sentimentScore = emp.Overall_Sentiment_Score__c;
            card.hasMatchingRoles = checkRoleMatch(emp, candidate);
            
            // Provide defaults if missing
            if (card.highlights == null || card.highlights.isEmpty()) {
                card.highlights = new List<String>{'Growing company', 'Great culture'};
            }
            
            cards.add(card);
        }
        
        return cards;
    }
    
    /**
     * Formats employee count into human-readable range.
     * Example: 750 → "500-1000 employees"
     */
    private static String formatEmployeeCount(Decimal count) {
        if (count == null) return 'Company size unknown';
        if (count < 10) return '1-10 employees';
        if (count < 50) return '10-50 employees';
        if (count < 200) return '50-200 employees';
        if (count < 500) return '200-500 employees';
        if (count < 1000) return '500-1000 employees';
        if (count < 5000) return '1000-5000 employees';
        return '5000+ employees';
    }
    
    /**
     * Formats salary range for display.
     * Examples: "$80k - $120k", "From $60k", "Up to $150k"
     */
    private static String formatSalaryRange(Decimal min, Decimal max) {
        if (min == null && max == null) return null;
        
        if (min != null && max != null) {
            return '$' + formatCurrency(min) + ' - $' + formatCurrency(max);
        }
        if (min != null) {
            return 'From $' + formatCurrency(min);
        }
        return 'Up to $' + formatCurrency(max);
    }
    
    /**
     * Formats currency number to K notation.
     * Example: 80000 → "80k"
     */
    private static String formatCurrency(Decimal amount) {
        if (amount == null) return '0';
        if (amount >= 1000) {
            return String.valueOf((amount / 1000).setScale(0)) + 'k';
        }
        return String.valueOf(amount.setScale(0));
    }
    
    /**
     * Parses JSON array string into List<String>.
     * Returns empty list if parsing fails.
     */
    /**
     * Parses string into List<String>.
     * Supports JSON array format OR comma-separated format.
     */
    private static List<String> parseJsonArray(String inputString) {
        if (String.isBlank(inputString)) {
            return new List<String>();
        }
    
        // Try JSON format first: ["IT","Management","Sales"]
        if (inputString.trim().startsWith('[')) {
            try {
                return (List<String>) JSON.deserialize(inputString, List<String>.class);
            } catch (Exception e) {
                System.debug('JSON parse failed, trying comma-separated: ' + e.getMessage());
            }
        }
    
        // Parse as comma-separated: IT,Management,Sales
        List<String> result = new List<String>();
        for (String val : inputString.split(',')) {
            String trimmed = val.trim();
            if (String.isNotBlank(trimmed)) {
                result.add(trimmed);
            }
        }
        
        return result;
    }
    
    /**
     * Checks if employer's typical roles match candidate's target role.
     */
    private static Boolean checkRoleMatch(Account employer, Contact candidate) {
        // Need career intent to check match
        if (candidate.Career_Intents__r == null || candidate.Career_Intents__r.isEmpty()) {
            return false;
        }
        
        String targetRole = candidate.Career_Intents__r[0].Target_Role__c;
        
        // Need both target role and employer's typical roles
        if (String.isBlank(targetRole) || String.isBlank(employer.Typical_Roles__c)) {
            return false;
        }
        
        // Case-insensitive contains check
        return employer.Typical_Roles__c.toLowerCase().contains(targetRole.toLowerCase());
    }
}
